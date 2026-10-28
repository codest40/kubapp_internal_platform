import subprocess
import time
from datetime import datetime
import uuid
from pathlib import Path

from command_policy import ensure_command_is_safe
from component_execution_env import (
    ComponentEnvironment,
    ComponentEnvironmentError,
)

def get_latest_commit_id():
    result = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        return f"{uuid.uuid4().hex[:5]}-uuid"
    return result.stdout.strip()[:10]


def get_timestamp():
    return datetime.now().strftime("%Y-%m-%d-%H-%M-%S")


def get_root(arg=None):
    result = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        capture_output=True,
        text=True,
    )

    if result.returncode != 0:
        return False

    root = result.stdout.strip()
    return Path(root) if arg == "path" else root


def start_timer():
    return time.perf_counter()

def BIG_LINE(arg=None):
  if not arg:
    arg = "-"
  print(arg * 80)

def line_logger(char="=", length=30):
    """Print a separator line using the specified character and length."""
    if not isinstance(char, str) or not char.strip():
        raise ValueError("char must be a non-empty string")

    if not isinstance(length, int) or isinstance(length, bool) or length < 1:
        raise ValueError("length must be a positive integer")

    return char * length


def ci_log(message, level="INFO"):
    prefix = {
        "INFO": "ℹ️",
        "SUCCESS": "✅",
        "WARNING": "⚠️",
        "ERROR": "❌",
        "DEBUG": "🔍",
    }.get(level.upper(), "ℹ️")

    print(f"{prefix} {message}")


def _print_result(result):
    if result.stdout:
        print(result.stdout, end="")

    if result.stderr:
        print(result.stderr, end="")


def run_platform_command(command, cwd=None, label=None, env=None):
    """Run a trusted platform command using the existing subprocess behavior."""
    try:
        result = subprocess.run(
            command,
            cwd=cwd,
            env=env,
            check=True,
            text=True,
            capture_output=True,
        )
        _print_result(result)
        return result

    except subprocess.CalledProcessError as exc:
        ci_log(
            f"{label or 'Platform command'} failed "
            f"(exit code {exc.returncode})",
            "ERROR",
        )
        if exc.stdout:
            print(exc.stdout, end="")
        if exc.stderr:
            print(exc.stderr, end="")
        raise


def run_component_command(
    command,
    component_environment,
    cwd=None,
    label=None,
    timeout_seconds=None,
):
    if not isinstance(component_environment, ComponentEnvironment):
        raise TypeError(
            "component_environment must be a ComponentEnvironment instance"
        )

    try:
        result = component_environment.run(
            command=command,
            cwd=cwd,
            label=label or "Component command",
            timeout_seconds=timeout_seconds,
        )

        _print_result(result)
        return result

    except ComponentEnvironmentError as exc:
        ci_log(
            f"{label or 'Component command'} failed: {exc}",
            level="ERROR",
        )
        raise

def run_extra_checks(
    extra_ci_config,
    runtime,
    app_name,
    app_dir,
    component_environment,
):
    """Run developer-defined checks through the component execution boundary."""
    for check_name, command in extra_ci_config.items():
        ci_log(
            f"[{app_name}] Running extra check: {check_name}",
            "INFO",
        )

        command = ensure_command_is_safe(command, runtime)

        run_component_command(
            command,
            component_environment=component_environment,
            cwd=app_dir,
            label=f"[{app_name}] Extra check: {check_name}",
        )

        ci_log(
            f"[{app_name}] Extra check passed: {check_name}",
            "SUCCESS",
        )

def collect_content(file_path, allowed_root=None):
    """
    Read a regular file as text without executing it.
    """
    if not isinstance(file_path, (str, Path)):
        raise TypeError("file_path must be a string or Path.")

    if not str(file_path).strip():
        raise ValueError("file_path cannot be empty.")

    path = Path(file_path).resolve()

    if allowed_root is not None:
        if not isinstance(allowed_root, (str, Path)):
            raise TypeError("allowed_root must be a string or Path.")

        root = Path(allowed_root).resolve()
        try:
            path.relative_to(root)
        except ValueError as exc:
            raise ValueError(
                f"File must be inside the permitted directory: {root}"
            ) from exc

    if not path.is_file():
        raise FileNotFoundError(
            f"File does not exist or is not a regular file: {path}"
        )

    try:
        return path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as exc:
        raise RuntimeError(
            f"Failed to read file content: {path}"
        ) from exc
