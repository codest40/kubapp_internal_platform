# KUBAPP CI — LLM Provider Setup and Validation

## Overview

`setup_provider.py` prepares the Large Language Model (LLM) provider used by KUBAPP's AI assessment system.

It supports three providers:

- **Ollama** — installs Ollama if necessary, starts a managed server, and ensures the configured model is available.
- **OpenAI** — validates API credentials and confirms that the selected model appears in the models returned for the API key.
- **Google Gemini** — validates API credentials and confirms that the selected model appears in the models returned by the Google API.

The script resolves the provider and model from environment variables, performs the corresponding setup or validation, and exits with a status code indicating success or failure.

Provider setup is separate from artifact assessment. This module prepares or validates provider access; it does not assess application artifacts or make CI approval decisions.

## 1. Provider and Model Configuration

### Supported providers

The supported values for `LLM_PROVIDER` are:

| Provider | Required model variable | Credential requirement |
|---|---|---|
| `ollama` | `OLLAMA_MODEL` | No API key is checked by this module |
| `openai` | `OPENAI_MODEL` | `OPENAI_API_KEY` |
| `google` | `GOOGLE_MODEL` | `GOOGLE_API_KEY` |

`LLM_PROVIDER` defaults to `ollama` and is normalized to lowercase.

Unsupported provider values raise `ProviderSetupError`.

### Model selection

`get_model(provider)` selects the provider-specific model variable. An empty model setting causes setup to fail.

The error message also mentions `LLM_MODEL`, but the implementation does not read `LLM_MODEL` as a fallback. The effective configuration must therefore provide the appropriate provider-specific variable.

### Diagnostic output

`get_setting()` trims environment values and prints temporary diagnostics for:

- `LLM_PROVIDER`
- `OLLAMA_MODEL`
- `OPENAI_MODEL`
- `GOOGLE_MODEL`
- `OLLAMA_HOST`

These diagnostics show the configured value and whether it is present. They do not print the API keys handled by this module.

**Operational consideration:** The selected provider and model names can appear in CI logs. Avoid putting secrets in configuration variables that are logged by this diagnostic function.

## 2. Ollama Host Normalization

`normalize_ollama_host()` resolves the Ollama HTTP endpoint and server bind address.

The default is:

`127.0.0.1:11434`

If the configured value has no scheme, the function adds `http://`.

The function rejects configurations that use:
- A scheme other than HTTP.
- An empty hostname.
- A path other than an empty path or `/`.
- A query string or fragment.
- Embedded username or password credentials.
- An invalid port.

If no port is specified, the bind address uses port `80`.

The function returns two values:

- **Endpoint:** The HTTP URL used by the setup process to contact Ollama.
- **Bind address:** The hostname and port assigned to the managed Ollama server.

IPv6 hostnames are bracketed when constructing the bind address.

**Important:** This implementation requires HTTP, not HTTPS, for the Ollama endpoint. The configured host should therefore be appropriate for the environment in which the setup script runs.

## 3. Ollama Installation

`install_ollama_if_needed()` checks whether the `ollama` executable is available on the system.

If it is already installed, the function returns without reinstalling it.

Otherwise, automatic installation requires:
- Linux.
- `curl`.
- `sudo`.

The installer is downloaded from the official Ollama installation script endpoint to:

`/tmp/kubapp-ollama-install.sh`

The script then executes the downloaded installer through `sudo sh`, with a 600-second timeout. The temporary installer file is removed in a `finally` block.

After installation, the function checks whether the `ollama` executable can be found.

Failures are reported through `ProviderSetupError`.

**Security consideration:** This installation path executes a remotely downloaded shell script with elevated privileges. The code downloads the script and executes it but does not independently verify a pinned version, checksum, or signature before execution.

## 4. Managed Ollama Server Lifecycle

### Model directory

`start_ollama_server()` resolves the model directory from `OLLAMA_MODELS`.

If that variable is empty or unset, the default is:

`~/.ollama/models`

The directory is created if necessary.

### Process metadata

The setup script stores managed-process metadata in `RUNNER_TEMP` when that variable is configured; otherwise, it uses `/tmp`.

| File | Purpose |
|---|---|
| `kubapp-ollama.pid` | Records the managed server process ID |
| `kubapp-ollama.log` | Receives the managed server's standard output and standard error |

These files allow subsequent setup runs to identify and stop a previously managed server.

### Stopping a previous process

`stop_managed_ollama()` reads the recorded PID and inspects `/proc/<pid>/cmdline`.

Before signalling a process, it checks that the executable is named `ollama` and that `serve` appears among its arguments. This helps avoid signalling an unrelated process if the PID has been reused.

The function sends `SIGTERM`, waits for up to approximately five seconds, and sends `SIGKILL` if the matching process remains. It removes the PID file when handling the recorded process.

`stop_system_ollama_service()` also attempts to stop the packaged `ollama` system service through `sudo systemctl stop ollama`, when both `systemctl` and `sudo` are available.

A service-stop failure is ignored because it does not, by itself, prove that an Ollama endpoint remains active.

### Refusing an unmanaged server

After attempting to stop the managed process and system service, the script checks whether the configured endpoint is already responding.

If it finds a responding server, setup fails rather than reusing it. The reason is that the script cannot verify whether that server uses the configured model directory.

This behavior is intended to avoid silently using a server whose model state cannot be associated with the setup process's configured directory.

### Starting the server

The script starts:

`ollama serve`

It passes an environment containing the configured `OLLAMA_HOST` bind address and resolved `OLLAMA_MODELS` directory.

The process:
- Runs in a new session.
- Receives no standard input.
- Writes output to the managed log file.
- Has its PID recorded for later cleanup.

The script polls the endpoint up to 60 times, sleeping two seconds between unsuccessful checks. This provides approximately two minutes of readiness polling.

If the process exits before readiness, setup fails and points to the log file. If readiness is not achieved within the polling window, setup also fails.

**Operational consideration:** If startup times out while the process remains alive, this function does not explicitly terminate that process in its timeout branch. The PID file and process may therefore require cleanup on a later run.

## 5. Ollama Model Availability

`get_ollama_models(endpoint)` requests:

`GET /api/tags`

It validates the HTTP response and expects a JSON object containing a `models` list. Entries with string-valued `name` fields are collected into a set.

`ensure_ollama_model(endpoint, model)` checks whether the requested model is already present.

- If present, no download is attempted.
- If absent, the script requests `POST /api/pull` with the selected model name and `stream: false`.
- After a successful HTTP response, it queries the model list again.
- If the model is still missing, setup fails.

The model-pull request has a configured timeout of 3600 seconds.

This confirms that Ollama reports the requested model as available. It does not independently verify model provenance or a pinned model digest.

## 6. OpenAI Validation

`prepare_openai(model)` validates OpenAI access without installing or downloading a model locally.

The function requires `OPENAI_API_KEY` and requests:

`GET https://api.openai.com/v1/models`

It sends the API key using a Bearer authorization header.

The response must be a JSON object containing a `data` list. The script extracts string-valued `id` fields and checks whether the configured model appears in that set.

If the API request fails, the response is unsuccessful, the response format is unexpected, or the selected model is absent, setup fails.

A successful result means that the API key can retrieve a model list containing the configured model ID. It does not prove that every operation supported by KUBAPP's later assessment requests will succeed.

## 7. Google Gemini Validation

`prepare_google(model)` requires `GOOGLE_API_KEY` and requests:

`GET https://generativelanguage.googleapis.com/v1beta/models`

The request includes `pageSize=1000` and sends the API key through the `x-goog-api-key` header.

The response must contain a `models` list. The script normalizes model names by removing an optional `models/` prefix and compares the result against the configured model.

If the selected model is not present in the returned list, setup fails.

A successful result establishes that the configured model appears in the API response. The function does not separately verify every permission or generation capability required by subsequent assessment calls.

## 8. HTTP and Subprocess Error Handling

### `ProviderSetupError`

`ProviderSetupError` represents an expected provider preparation or validation failure.

The main function catches this exception, prints a sanitized error message to standard error, and returns exit code `1`.

Unexpected exceptions are caught separately. The script prints a generic unexpected-failure message and also returns `1`.

Successful preparation returns exit code `0`.

### HTTP helper

`http_get()` performs a GET request and checks that:
- The request completes without an `httpx.HTTPError`.
- The status code is in the HTTP 2xx range.
- The response contains valid JSON.
- The decoded response is a JSON object.

It reports a concise error instead of printing arbitrary response bodies.

The helper does not validate provider-specific response fields; those checks are performed by the relevant provider functions.

### Subprocess helper

`run_checked()` executes a command with captured text output and a timeout. It raises `ProviderSetupError` if the command cannot run, times out, or exits with a nonzero status.

The helper does not include arbitrary subprocess output in its error message.

### Timeout configuration

| Operation | Timeout or polling behavior |
|---|---|
| Default checked subprocess | 300 seconds |
| Ollama installer execution | 600 seconds |
| Provider HTTP GET requests | 30 seconds |
| Ollama readiness request | 5 seconds per request |
| Ollama model pull | 3600 seconds |
| Ollama readiness polling | Up to 60 attempts, with two-second intervals |
| System service stop | 30 seconds |
| Managed-process termination wait | Approximately 5 seconds before `SIGKILL` |

The Ollama readiness polling window and HTTP request timeout are separate mechanisms. The total elapsed time can vary with individual request durations and scheduling.

## 9. Execution Flow

The `main()` function follows this sequence:

1. Resolve and validate `LLM_PROVIDER`.
2. Resolve the provider-specific model setting.
3. Print the selected provider and model.
4. Run the corresponding provider preparation function.
5. Print a success message and return `0` if preparation completes.
6. Return `1` if an expected or unexpected failure occurs.

Provider-specific behavior is selected explicitly for Ollama, OpenAI, and Google Gemini.

## 10. Responsibility Boundaries

This module is responsible for preparing or validating the configured LLM provider. It is not responsible for:

- Assessing source files, scripts, modules, or Dockerfiles.
- Validating the final assessment decision.
- Persisting or committing AI assessment reports.
- Enforcing whether a rejected artifact may execute.
- Sandboxing application build commands.
- Guaranteeing that provider credentials are authorized for every later API operation.

Those responsibilities belong to other parts of the KUBAPP CI and AI assessment flow.

## 11. Related Modules

| Module | Responsibility |
|---|---|
| `ai/server.py` | Exposes the assessment MCP tool and dispatches provider requests. |
| `ai/client.py` | Connects to the MCP server and validates assessment requests and results. |
| `ai_analysis.py` | Prepares artifact assessment context and invokes the assessment client. |
| `platform_decision.py` | Validates assessment results and records the resulting decision. |

## Summary

`setup_provider.py` centralizes provider selection, model configuration, Ollama installation and lifecycle management, Ollama model availability, and remote-provider access validation.

Its success status confirms that the configured provider preparation steps completed. It should not be interpreted as proof that later assessments will always succeed, that model behavior is trustworthy, or that CI execution is isolated.
