"""
Prepare the selected KUBAPP LLM provider.
"""

import os
import platform
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path
from urllib.parse import urlsplit

import httpx


SUPPORTED_PROVIDERS = {"ollama", "openai", "google"}
REQUEST_TIMEOUT = 30.0
OLLAMA_START_ATTEMPTS = 60
OLLAMA_START_INTERVAL = 2
OLLAMA_PULL_TIMEOUT = 3600.0


class ProviderSetupError(RuntimeError):
    """Raised when the selected provider cannot be prepared."""


def get_setting(name, default=""):
    """Return a trimmed environment setting with temporary diagnostics."""
    value = os.environ.get(name, default).strip()

    diagnostic_names = {
        "LLM_PROVIDER",
        "OLLAMA_MODEL",
        "OPENAI_MODEL",
        "GOOGLE_MODEL",
        "OLLAMA_HOST",
    }

    if name in diagnostic_names:
        print(
            f"[PROVIDER DEBUG] {name}: "
            f"{value!r} (present={bool(value)})",
            file=sys.stderr,
            flush=True,
        )
    return value

def get_provider():
    """Resolve and validate the selected provider."""
    provider = get_setting("LLM_PROVIDER", "ollama").lower()

    if provider not in SUPPORTED_PROVIDERS:
        supported = ", ".join(sorted(SUPPORTED_PROVIDERS))
        raise ProviderSetupError(
            f"Unsupported LLM_PROVIDER={provider!r}. "
            f"Supported providers: {supported}."
        )
    return provider


def get_model(provider):
    """Resolve the common model setting or provider-specific fallback."""
    model_variable = {
        "ollama": "OLLAMA_MODEL",
        "openai": "OPENAI_MODEL",
        "google": "GOOGLE_MODEL",
    }[provider]

    model =  get_setting(model_variable)

    if not model:
        raise ProviderSetupError(
            f"No model configured for provider {provider!r}. "
            f"Set LLM_MODEL or {model_variable}."
        )

    return model


def normalize_ollama_host():
    """Return the HTTP endpoint and Ollama server bind address."""
    configured_host = get_setting(
        "OLLAMA_HOST",
        "127.0.0.1:11434",
    )

    if "://" not in configured_host:
        configured_host = f"http://{configured_host}"

    parsed = urlsplit(configured_host)

    if (
        parsed.scheme != "http"
        or not parsed.hostname
        or parsed.path not in {"", "/"}
        or parsed.query
        or parsed.fragment
        or parsed.username
        or parsed.password
    ):
        raise ProviderSetupError(
            "OLLAMA_HOST must be a valid HTTP host and port, "
            "without a path, query, credentials, or fragment."
        )

    try:
        port = parsed.port
    except ValueError as exc:
        raise ProviderSetupError(
            "OLLAMA_HOST contains an invalid port."
        ) from exc

    if port is None:
        port = 80

    hostname = parsed.hostname

    if ":" in hostname:
        hostname = f"[{hostname}]"

    endpoint = f"http://{parsed.netloc}"
    bind_address = f"{hostname}:{port}"

    return endpoint, bind_address


def run_checked(command, label, timeout=300):
    """Run a command without exposing arbitrary command output."""
    try:
        result = subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise ProviderSetupError(
            f"{label} could not be completed."
        ) from exc

    if result.returncode != 0:
        raise ProviderSetupError(
            f"{label} failed with exit code {result.returncode}."
        )

    return result


def http_get(client, url, label, **kwargs):
    """Perform an HTTP GET with sanitized error reporting."""
    try:
        response = client.get(url, **kwargs)
    except httpx.HTTPError as exc:
        raise ProviderSetupError(
            f"{label} failed. Check network connectivity "
            "and provider configuration."
        ) from exc

    if not 200 <= response.status_code < 300:
        raise ProviderSetupError(
            f"{label} returned HTTP {response.status_code}. "
            "Check credentials, permissions, and configuration."
        )

    try:
        data = response.json()
    except ValueError as exc:
        raise ProviderSetupError(
            f"{label} returned invalid JSON."
        ) from exc

    if not isinstance(data, dict):
        raise ProviderSetupError(
            f"{label} returned an unexpected response format."
        )

    return data


def install_ollama_if_needed():
    """Install Ollama only when its executable is unavailable."""
    if shutil.which("ollama"):
        print("[LLM setup] Ollama is already installed.")
        return

    if platform.system() != "Linux":
        raise ProviderSetupError(
            "Automatic Ollama installation currently supports Linux."
        )

    if not shutil.which("curl") or not shutil.which("sudo"):
        raise ProviderSetupError(
            "Installing Ollama requires curl and sudo."
        )

    installer = Path("/tmp/kubapp-ollama-install.sh")

    try:
        run_checked(
            [
                "curl",
                "-fsSL",
                "https://ollama.com/install.sh",
                "-o",
                str(installer),
            ],
            "Downloading the Ollama installer",
        )

        run_checked(
            ["sudo", "sh", str(installer)],
            "Installing Ollama",
            timeout=600,
        )
    finally:
        installer.unlink(missing_ok=True)

    if not shutil.which("ollama"):
        raise ProviderSetupError(
            "Ollama installation completed, but its executable "
            "could not be found."
        )

    print("[LLM setup] Ollama installed successfully.")


def ollama_is_ready(endpoint):
    """Check whether the Ollama API responds successfully."""
    try:
        response = httpx.get(
            f"{endpoint}/api/tags",
            timeout=5.0,
        )
        return response.status_code == 200
    except httpx.HTTPError:
        return False


def get_runner_path(filename):
    """Return a path for setup-script process metadata."""
    runner_temp = get_setting("RUNNER_TEMP")
    directory = Path(runner_temp) if runner_temp else Path("/tmp")
    return directory / filename


def get_managed_pid_path():
    return get_runner_path("kubapp-ollama.pid")


def get_managed_log_path():
    return get_runner_path("kubapp-ollama.log")


def get_process_command(pid):
    """Read a Linux process command line, returning None if unavailable."""
    try:
        raw = Path(f"/proc/{pid}/cmdline").read_bytes()
    except OSError:
        return None

    return [
        item.decode("utf-8", errors="replace")
        for item in raw.split(b"\0")
        if item
    ]


def is_ollama_server_process(pid):
    """Avoid signalling an unrelated process when a PID has been reused."""
    command = get_process_command(pid)

    if not command:
        return False

    executable = Path(command[0]).name.lower()

    return executable == "ollama" and "serve" in command[1:]


def stop_managed_ollama(pid_path):
    """Stop a previously managed Ollama process safely."""
    try:
        pid = int(pid_path.read_text(encoding="utf-8").strip())
    except (OSError, ValueError):
        pid_path.unlink(missing_ok=True)
        return

    if not is_ollama_server_process(pid):
        pid_path.unlink(missing_ok=True)
        return

    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        pid_path.unlink(missing_ok=True)
        return
    except PermissionError as exc:
        raise ProviderSetupError(
            "Cannot stop the previously managed Ollama process."
        ) from exc

    for _ in range(50):
        if not is_ollama_server_process(pid):
            pid_path.unlink(missing_ok=True)
            return
        time.sleep(0.1)

    if is_ollama_server_process(pid):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        except PermissionError as exc:
            raise ProviderSetupError(
                "Cannot terminate the previous Ollama process."
            ) from exc

    pid_path.unlink(missing_ok=True)


def stop_system_ollama_service():
    """Stop the packaged service so it cannot use another model directory."""
    if not shutil.which("systemctl") or not shutil.which("sudo"):
        return

    try:
        subprocess.run(
            ["sudo", "systemctl", "stop", "ollama"],
            check=False,
            capture_output=True,
            text=True,
            timeout=30,
        )
    except (OSError, subprocess.TimeoutExpired):
        # service-stop failure alone is
        # not proof that the endpoint is still active.
        pass


def start_ollama_server(endpoint, bind_address):
    """
    Start an Ollama server using the configured model directory.
    An already responding unmanaged server is rejected because this
    script cannot prove that it uses the restored GitHub cache.
    """
    models_dir = Path(
        get_setting(
            "OLLAMA_MODELS",
            str(Path.home() / ".ollama" / "models"),
        )
    ).expanduser().resolve()

    try:
        models_dir.mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        raise ProviderSetupError(
            "Could not create the configured Ollama model directory."
        ) from exc

    pid_path = get_managed_pid_path()
    log_path = get_managed_log_path()

    stop_managed_ollama(pid_path)
    stop_system_ollama_service()

    if ollama_is_ready(endpoint):
        raise ProviderSetupError(
            "An unmanaged Ollama server is already responding at "
            "OLLAMA_HOST. Refusing to reuse it because its model "
            "directory cannot be verified. Stop that server or "
            "configure an unused local endpoint."
        )

    server_environment = os.environ.copy()
    server_environment["OLLAMA_HOST"] = bind_address
    server_environment["OLLAMA_MODELS"] = str(models_dir)

    try:
        with log_path.open("a", encoding="utf-8") as log_file:
            process = subprocess.Popen(
                ["ollama", "serve"],
                env=server_environment,
                stdin=subprocess.DEVNULL,
                stdout=log_file,
                stderr=subprocess.STDOUT,
                start_new_session=True,
            )
    except OSError as exc:
        raise ProviderSetupError(
            "Failed to start the Ollama server."
        ) from exc

    pid_path.write_text(
        f"{process.pid}\n",
        encoding="utf-8",
    )

    for _ in range(OLLAMA_START_ATTEMPTS):
        if process.poll() is not None:
            pid_path.unlink(missing_ok=True)
            raise ProviderSetupError(
                "Ollama exited before becoming ready. "
                f"Inspect its log at {log_path}."
            )

        if ollama_is_ready(endpoint):
            print("[LLM setup] Ollama server is ready.")
            print(f"[LLM setup] Model directory: {models_dir}")
            return

        time.sleep(OLLAMA_START_INTERVAL)

    raise ProviderSetupError(
        "Ollama did not become ready within the allowed time. "
        f"Inspect its log at {log_path}."
    )


def get_ollama_models(endpoint):
    """Return model names reported by the Ollama API."""
    try:
        with httpx.Client(timeout=REQUEST_TIMEOUT) as client:
            data = http_get(
                client,
                f"{endpoint}/api/tags",
                "Checking available Ollama models",
            )
    except httpx.HTTPError as exc:
        raise ProviderSetupError(
            "Could not query available Ollama models."
        ) from exc

    models = data.get("models")

    if not isinstance(models, list):
        raise ProviderSetupError(
            "Ollama returned an unexpected model-list response."
        )

    return {
        item["name"]
        for item in models
        if isinstance(item, dict)
        and isinstance(item.get("name"), str)
    }


def ensure_ollama_model(endpoint, model):
    """Pull the selected model only when it is not already available."""
    if model in get_ollama_models(endpoint):
        print(f"[LLM setup] Ollama model is available: {model}")
        return

    print(f"[LLM setup] Downloading Ollama model: {model}")

    try:
        with httpx.Client(timeout=OLLAMA_PULL_TIMEOUT) as client:
            response = client.post(
                f"{endpoint}/api/pull",
                json={
                    "name": model,
                    "stream": False,
                },
            )
    except httpx.HTTPError as exc:
        raise ProviderSetupError(
            f"Failed to download Ollama model {model!r}."
        ) from exc

    if not 200 <= response.status_code < 300:
        raise ProviderSetupError(
            f"Ollama could not download model {model!r}; "
            f"HTTP {response.status_code}."
        )

    if model not in get_ollama_models(endpoint):
        raise ProviderSetupError(
            f"Ollama pull completed, but model {model!r} "
            "was not found in the model list."
        )

    print(f"[LLM setup] Ollama model is ready: {model}")


def prepare_ollama(model):
    """Install Ollama, start its configured server, and ensure the model."""
    install_ollama_if_needed()

    endpoint, bind_address = normalize_ollama_host()

    start_ollama_server(
        endpoint=endpoint,
        bind_address=bind_address,
    )

    ensure_ollama_model(endpoint, model)


def prepare_openai(model):
    """Validate OpenAI credentials, connectivity, and model visibility."""
    api_key = get_setting("OPENAI_API_KEY")

    if not api_key:
        raise ProviderSetupError(
            "OPENAI_API_KEY is required when LLM_PROVIDER=openai."
        )

    print("[LLM setup] Checking OpenAI API access.")

    with httpx.Client(timeout=REQUEST_TIMEOUT) as client:
        data = http_get(
            client,
            "https://api.openai.com/v1/models",
            "OpenAI API validation",
            headers={
                "Authorization": f"Bearer {api_key}",
            },
        )

    models = data.get("data")

    if not isinstance(models, list):
        raise ProviderSetupError(
            "OpenAI returned an unexpected model-list response."
        )

    available = {
        item["id"]
        for item in models
        if isinstance(item, dict)
        and isinstance(item.get("id"), str)
    }

    if model not in available:
        raise ProviderSetupError(
            f"OpenAI model {model!r} was not found in the models "
            "returned for this API key. Verify the model name "
            "and account permissions."
        )

    print(f"[LLM setup] OpenAI model is visible: {model}")


def prepare_google(model):
    """Validate Google Gemini credentials and model visibility."""
    api_key = get_setting("GOOGLE_API_KEY")

    if not api_key:
        raise ProviderSetupError(
            "GOOGLE_API_KEY is required when LLM_PROVIDER=google."
        )

    print("[LLM setup] Checking Google Gemini API access.")

    with httpx.Client(timeout=REQUEST_TIMEOUT) as client:
        data = http_get(
            client,
            "https://generativelanguage.googleapis.com/v1beta/models",
            "Google Gemini API validation",
            headers={
                "x-goog-api-key": api_key,
            },
            params={
                "pageSize": 1000,
            },
        )

    models = data.get("models")

    if not isinstance(models, list):
        raise ProviderSetupError(
            "Google returned an unexpected model-list response."
        )

    normalized_model = model.removeprefix("models/")

    available = {
        item["name"].removeprefix("models/")
        for item in models
        if isinstance(item, dict)
        and isinstance(item.get("name"), str)
    }

    if normalized_model not in available:
        raise ProviderSetupError(
            f"Google model {model!r} was not found in the models "
            "returned by the API. Verify the model name and access."
        )

    print(f"[LLM setup] Google Gemini model is visible: {model}")


def main():
    """Resolve and prepare the configured provider."""
    try:
        provider = get_provider()
        model = get_model(provider)

        print(f"[LLM setup] Provider: {provider}")
        print(f"[LLM setup] Model: {model}")

        if provider == "ollama":
            prepare_ollama(model)
        elif provider == "openai":
            prepare_openai(model)
        elif provider == "google":
            prepare_google(model)

        print(f"[LLM setup] Provider {provider!r} is prepared.")
        return 0

    except ProviderSetupError as exc:
        print(f"[LLM setup] ERROR: {exc}", file=sys.stderr)
        return 1
    except Exception:
        print(
            "[LLM setup] ERROR: Unexpected provider setup failure.",
            file=sys.stderr,
        )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
