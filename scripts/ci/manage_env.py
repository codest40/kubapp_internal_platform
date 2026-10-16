import os
import re
import subprocess
from pathlib import Path

import yaml

from reuse import ci_log

ENV_NAME_PATTERN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def load_component_secrets(app_name, secret_file):
    """
    Load, decrypt, and validate a component's CI secrets file.
    """
    if secret_file is None:
        ci_log(
            f"[{app_name}] No CI secrets file configured.",
            "DEBUG",
        )
        return {}

    secrets_path = Path(secret_file).resolve()

    if not secrets_path.is_file():
        message = (
            f"[{app_name}] Configured CI secrets file is missing "
            "or is not a regular file."
        )
        ci_log(message, "ERROR")
        raise RuntimeError(message)

    try:
        file_content = secrets_path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as exc:
        message = (
            f"[{app_name}] Unable to read the CI secrets file."
        )
        ci_log(message, "ERROR")
        raise RuntimeError(message) from exc

    if not file_content.strip():
        ci_log(
            f"[{app_name}] CI secrets file is empty.",
            "WARNING",
        )
        return {}

    ci_log(
        f"[{app_name}] Decrypting CI secrets file.",
        "INFO",
    )

    try:
        result = subprocess.run(
            ["sops", "--decrypt", str(secrets_path)],
            capture_output=True,
            text=True,
            check=False,
        )
    except FileNotFoundError as exc:
        message = (
            f"[{app_name}] SOPS is not installed or "
            "is not available on PATH."
        )
        ci_log(message, "ERROR")
        raise RuntimeError(message) from exc
    except OSError as exc:
        message = (
            f"[{app_name}] Unable to execute SOPS."
        )
        ci_log(message, "ERROR")
        raise RuntimeError(message) from exc

    if result.returncode != 0:
        message = (
            f"[{app_name}] Failed to decrypt the CI secrets file. "
            "Check SOPS configuration and Age key access."
        )
        ci_log(message, "ERROR")
        raise RuntimeError(message)

    try:
        document = yaml.safe_load(result.stdout)
    except yaml.YAMLError as exc:
        message = (
            f"[{app_name}] Decrypted CI secrets contain invalid YAML."
        )
        ci_log(message, "ERROR")
        raise RuntimeError(message) from exc

    if not isinstance(document, dict):
        message = (
            f"[{app_name}] CI secrets file must contain "
            "a YAML mapping."
        )
        ci_log(message, "ERROR")
        raise RuntimeError(message)

    secrets = document.get("secrets")

    if not isinstance(secrets, dict):
        message = (
            f"[{app_name}] CI secrets file must contain "
            "a top-level 'secrets' mapping."
        )
        ci_log(message, "ERROR")
        raise RuntimeError(message)

    validated_secrets = {}

    for name, value in secrets.items():
        if (
            not isinstance(name, str)
            or not ENV_NAME_PATTERN.fullmatch(name)
        ):
            message = (
                f"[{app_name}] CI secrets file contains an invalid "
                "environment variable name."
            )
            ci_log(message, "ERROR")
            raise RuntimeError(message)

        if not isinstance(value, str):
            message = (
                f"[{app_name}] CI secret '{name}' must have "
                "a string value."
            )
            ci_log(message, "ERROR")
            raise RuntimeError(message)

        validated_secrets[name] = value

    ci_log(
        f"[{app_name}] Validated {len(validated_secrets)} "
        "CI secret variable(s).",
        "SUCCESS",
    )

    return validated_secrets


def prepare_component_environment(app_name, secret_file, security_env):
    """
    Prepare an isolated environment for one CI component.
    """
    if security_env is None:
        security_env = []

    if not isinstance(security_env, list):
        message = (
            f"[{app_name}] security_env must be a list."
        )
        ci_log(message, "ERROR")
        raise RuntimeError(message)

    for variable in security_env:
        if (
            not isinstance(variable, str)
            or not ENV_NAME_PATTERN.fullmatch(variable)
        ):
            message = (
                f"[{app_name}] security_env contains an invalid "
                "environment variable name."
            )
            ci_log(message, "ERROR")
            raise RuntimeError(message)

    if len(security_env) != len(set(security_env)):
        message = (
            f"[{app_name}] security_env contains duplicate "
            "variable names."
        )
        ci_log(message, "ERROR")
        raise RuntimeError(message)

    if security_env and secret_file is None:
        message = (
            f"[{app_name}] security_env declares required CI secrets, "
            "but no CI secrets file is configured."
        )
        ci_log(message, "ERROR")
        raise RuntimeError(message)

    secrets = load_component_secrets(app_name, secret_file)

    if security_env and not secrets:
        message = (
            f"[{app_name}] security_env declares required CI secrets, "
            "but the component's secrets file is empty or contains "
            "no secret variables."
        )
        ci_log(message, "ERROR")
        raise RuntimeError(message)

    for variable in security_env:
        if not secrets.get(variable):
            message = (
                f"[{app_name}] Required CI secret '{variable}' "
                "is missing or empty in the component's secrets file."
            )
            ci_log(message, "ERROR")
            raise RuntimeError(message)

    component_env = os.environ.copy()
    component_env.update(secrets)

    ci_log(
        f"[{app_name}] Component environment prepared successfully.",
        "SUCCESS",
    )

    return component_env
