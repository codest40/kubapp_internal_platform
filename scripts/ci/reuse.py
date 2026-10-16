import os
from pathlib import Path
import subprocess
import time
from datetime import datetime
import uuid
from command_policy import ensure_command_is_safe

def get_latest_commit_id():
    id = subprocess.run(["git", "rev-parse", "HEAD"],
         capture_output=True, text=True)
    if id.returncode != 0:
        id = f"{uuid.uuid4().hex[:5]}-uuid"
    return id.stdout.strip()[:10]

def get_timestamp():
    TS = datetime.now().strftime("%Y-%m-%d-%H-%M-%S")
    return TS

def get_root(arg=None):
    result = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        capture_output=True,
        text=True,
    )

    if result.returncode != 0:
        return False
    root = result.stdout.strip()

    if arg == "path":
        return Path(root)
    return root

def start_timer():
    return time.perf_counter()


def line_logger(char="=", length=30):
    """Print a separator line using the specified character and length."""
    if not isinstance(char, str) or not char or not char.strip():
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


def run_command(command, cwd=None, label=None, env=None):
    try:
        result = subprocess.run(
            command,
            cwd=cwd,
            env=env,
            check=True,
            text=True,
            capture_output=True,
        )

        if result.stdout:
            print(result.stdout, end="")

        if result.stderr:
            print(result.stderr, end="")

        return result

    except subprocess.CalledProcessError as e:
        ci_log(
            f"{label or 'Command'} failed "
            f"(exit code {e.returncode})",
            "ERROR",
        )

        if e.stdout:
            print(e.stdout, end="")
        if e.stderr:
            print(e.stderr, end="")
        raise

def run_extra_checks(extra_ci_config, runtime, app_name, app_dir, env=None,):
    for check_name, command in extra_ci_config.items():
        ci_log(
            f"[{app_name}] Running extra check: {check_name}",
            "INFO",
        )

        command = ensure_command_is_safe(command, runtime)
        run_command(
            command,
            cwd=app_dir,
            label=f"[{app_name}] Extra check: {check_name}",
            env=env,
        )

        ci_log(
            f"[{app_name}] Extra check passed: {check_name}",
            "SUCCESS",
        )
