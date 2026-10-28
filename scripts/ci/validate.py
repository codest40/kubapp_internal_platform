from pathlib import Path
import reuse
from detect_runtime import (
    discover_apps,
    get_runtime_handler,
    detect_runtime_from_manifests,
)
from variables import MANIFESTS, EXTRA_MANIFESTS

line = reuse.line_logger("=", 60)
PROJECT_ROOT = reuse.get_root("path")
SUPPORTED_FILE_PATH_KEYS = {
    "manifest_files",
    "docker_file",
    "kubapp_file",
    "secret_file",
}

REQUIRED_FILE_PATH_KEYS = {"docker_file"}
SUPPORTED_RUNTIMES = set(MANIFESTS.values())


def _log(message, level="INFO"):
    reuse.ci_log(message, level)


def _require_nonempty_string(value, field_name, errors):
    """Ensure a value is a nonempty string."""
    if not isinstance(value, str) or not value.strip():
        errors.append(
            f"{field_name} must be a nonempty string."
        )
        return False

    return True


def _require_string_list(value, field_name, errors, allow_empty=False):
    """Ensure a value is a list of nonempty strings."""
    if not isinstance(value, list):
        errors.append(
            f"{field_name} must be a list of strings."
        )
        return False

    if not allow_empty and not value:
        errors.append(
            f"{field_name} must not be empty."
        )
        return False

    valid = True

    for index, item in enumerate(value):
        if not isinstance(item, str) or not item.strip():
            errors.append(
                f"{field_name}[{index}] must be a nonempty string."
            )
            valid = False

    return valid


def _require_port(value, field_name, errors):
    """Validate a TCP/UDP port number."""
    if isinstance(value, bool) or not isinstance(value, int):
        errors.append(
            f"{field_name} must be an integer between 1 and 65535."
        )
        return False

    if not 1 <= value <= 65535:
        errors.append(
            f"{field_name} must be between 1 and 65535."
        )
        return False

    return True


def _require_file(path, field_name, errors, required=True):
    if path is None:
        if required:
            errors.append(
                f"{field_name} has no resolved file path."
            )
            return False

        return True

    path = Path(path)

    try:
        if not path.is_file():
            if required:
                errors.append(
                    f"{field_name} does not exist or is not a file: {path}"
                )
                return False

            return True

        if path.stat().st_size == 0:
            errors.append(
                f"{field_name} is empty: {path}"
            )
            return False

    except OSError as exc:
        errors.append(
            f"Unable to inspect {field_name} at {path}: {exc}"
        )
        return False

    return True


def _validate_security_env(config, errors):
    security_env = config.get("security_env", [])
    if security_env is None:
        security_env = []

    if not _require_string_list(
        security_env,
        "security_env",
        errors,
        allow_empty=True,
    ):
        return []

    if len(security_env) != len(set(security_env)):
        errors.append(
            "security_env must not contain duplicate variable names."
        )
    return security_env

def _validate_app_directory(app_dir, errors):
    """Ensure the candidate's application directory exists."""
    app_dir = Path(app_dir)

    try:
        if not app_dir.is_dir():
            errors.append(
                f"Application directory does not exist: {app_dir}"
            )
            return False

    except OSError as exc:
        errors.append(
            f"Unable to inspect application directory "
            f"{app_dir}: {exc}"
        )
        return False

    return True


def _validate_discovery_record(candidate, errors):
    if not isinstance(candidate, dict):
        errors.append(
            "Discovery returned an invalid application record."
        )
        return False

    discovery_errors = candidate.get("discovery_errors", [])

    if not isinstance(discovery_errors, list):
        errors.append(
            "Discovery errors must be provided as a list."
        )
    else:
        errors.extend(str(error) for error in discovery_errors)

    runtime_errors = candidate.get("runtime_detection_errors", [])

    if not isinstance(runtime_errors, list):
        errors.append(
            "Runtime detection errors must be provided as a list."
        )
    else:
        errors.extend(str(error) for error in runtime_errors)

    return not errors


def _validate_file_paths_config(config, errors):
    if "file_paths" not in config:
        return

    file_paths = config["file_paths"]
    if not isinstance(file_paths, dict):
        errors.append(
            "file_paths must be a mapping."
        )
        return

    unknown_keys = set(file_paths) - SUPPORTED_FILE_PATH_KEYS

    for key in sorted(unknown_keys):
        errors.append(
            f"Unsupported file_paths entry: {key}"
        )

    if "manifest_files" in file_paths:
        value = file_paths["manifest_files"]

        if isinstance(value, str):
            if not value.strip():
                errors.append(
                    "file_paths.manifest_files must not be empty."
                )

        elif isinstance(value, list):
            _require_string_list(
                value,
                "file_paths.manifest_files",
                errors,
            )

        else:
            errors.append(
                "file_paths.manifest_files must be a path string "
                "or a nonempty list of path strings."
            )

    for key in ("docker_file", "kubapp_file", "secret_file"):
        if key not in file_paths:
            continue

        _require_nonempty_string(
            file_paths[key],
            f"file_paths.{key}",
            errors,
        )


def _validate_runtime_config(config, errors):
    """Validate the runtime declared in ci.yml."""
    runtime = config.get("runtime")

    if not _require_nonempty_string(
        runtime,
        "runtime",
        errors,
    ):
        return None

    runtime = runtime.strip().lower()
    if runtime not in SUPPORTED_RUNTIMES:
        errors.append(
            f"Unsupported runtime declaration: {runtime}"
        )
        return None

    if get_runtime_handler(runtime) is None:
        errors.append(
            f"No CI handler is registered for runtime '{runtime}'."
        )
        return None
    return runtime

def _validate_ci_script_paths(
    ci_scripts,
    component_dir,
    app_name,
    errors,
):
    """Ensure configured CI scripts exist inside the component directory."""
    try:
        component_root = Path(component_dir).resolve(strict=True)
    except (OSError, RuntimeError) as exc:
        errors.append(
            f"{app_name}: unable to resolve component directory "
            f"for CI script validation: {exc}"
        )
        return

    if not component_root.is_dir():
        errors.append(
            f"{app_name}: component directory is not a directory: "
            f"{component_root}"
        )
        return

    for script in ci_scripts:
        if not isinstance(script, str) or not script.strip():
            continue

        script_path = Path(script)

        if script_path.is_absolute():
            errors.append(
                f"{app_name}: CI script path must be relative to the "
                f"component directory: {script}"
            )
            continue

        try:
            resolved_script = (
                component_root / script_path
            ).resolve(strict=True)
        except (OSError, RuntimeError):
            errors.append(
                f"{app_name}: CI script does not exist or cannot be "
                f"resolved: {script}"
            )
            continue

        try:
            resolved_script.relative_to(component_root)
        except ValueError:
            errors.append(
                f"{app_name}: CI script path escapes the component "
                f"directory: {script}"
            )
            continue
        if not resolved_script.is_file():
            errors.append(
                f"{app_name}: CI script is not a file: {script}"
            )
        if resolved_script.suffix.lower() not in {".py", ".sh"}:
            errors.append(
                f"{app_name}: unsupported CI script extension "
                f"'{resolved_script.suffix}'. Only .py and .sh "
                f"scripts are supported: {script}"
            )

def _validate_execution_config(config, errors):
    """Validate standard CI commands, custom scripts, and extra commands."""
    use_script = config.get("use_script", False)

    if not isinstance(use_script, bool):
        errors.append("use_script must be a boolean.")
        use_script = False

    ci_scripts = config.get("ci_scripts", [])
    if ci_scripts is None:
        ci_scripts = []

    if use_script:
        if not _require_string_list(
            ci_scripts,
            "ci_scripts",
            errors,
        ):
            ci_scripts = []

        ci_commands = config.get("ci_commands", {})
        if ci_commands not in ({}, None):
            errors.append(
                "ci_commands must be omitted or empty when "
                "use_script is true."
            )
    else:
        if not _require_string_list(
            ci_scripts,
            "ci_scripts",
            errors,
            allow_empty=True,
        ):
            ci_scripts = []

        ci_commands = config.get("ci_commands", {})
        if ci_commands is None:
            ci_commands = {}

        if not isinstance(ci_commands, dict):
            errors.append(
                "ci_commands must be a mapping when provided."
            )
            ci_commands = {}

    extra_ci_commands = config.get("extra_ci_commands", {})
    if extra_ci_commands is None:
        extra_ci_commands = {}

    if not isinstance(extra_ci_commands, dict):
        errors.append(
            "extra_ci_commands must be a mapping when provided."
        )
        extra_ci_commands = {}

    return {
        "use_script": use_script,

        "ci_scripts": ci_scripts,
        "ci_commands": ci_commands,
        "extra_ci_commands": extra_ci_commands,
    }

def _validate_healthcheck(extra_ci_config, errors):
    """Validate the additional CI configuration and container health checks."""
    if not isinstance(extra_ci_config, dict):
        errors.append(
            "extra_ci_config must be a mapping."
        )
        return {}

    if "healthcheck" not in extra_ci_config:
        errors.append(
            "extra_ci_config.healthcheck is required."
        )
        return extra_ci_config

    healthcheck = extra_ci_config["healthcheck"]

    if not isinstance(healthcheck, dict):
        errors.append(
            "extra_ci_config.healthcheck must be a mapping."
        )
        return extra_ci_config

    for port_name in ("app_port", "host_port"):
        if port_name not in healthcheck:
            errors.append(
                f"extra_ci_config.healthcheck.{port_name} is required."
            )
        else:
            _require_port(
                healthcheck[port_name],
                f"extra_ci_config.healthcheck.{port_name}",
                errors,
            )

    endpoints = healthcheck.get("endpoints")

    if _require_string_list(
        endpoints,
        "extra_ci_config.healthcheck.endpoints",
        errors,
    ):
        for index, endpoint in enumerate(endpoints):
            if not endpoint.startswith("/"):
                errors.append(
                    f"extra_ci_config.healthcheck.endpoints[{index}] "
                    "must begin with '/'."
                )

    expected_status = healthcheck.get("expected_status")

    if (
        isinstance(expected_status, bool)
        or not isinstance(expected_status, int)
        or not 100 <= expected_status <= 599
    ):
        errors.append(
            "extra_ci_config.healthcheck.expected_status must be "
            "an HTTP status code between 100 and 599."
        )
    return extra_ci_config

def _validate_manifest_paths(manifest_paths, runtime, errors):
    if not isinstance(manifest_paths, list):
        errors.append(
            "Discovered manifest_files paths must be a list."
        )
        return None, []

    if not manifest_paths:
        errors.append(
            "No recognized runtime manifests were discovered."
        )
        return None, []

    validated_paths = []
    runtime_manifest_paths = []
    extra_manifest_paths = []

    for manifest_path in manifest_paths:
        if not isinstance(manifest_path, (str, Path)):
            errors.append(
                f"Invalid discovered manifest path: {manifest_path!r}"
            )
            continue

        manifest_path = Path(manifest_path)
        filename = manifest_path.name

        runtime_for_manifest = MANIFESTS.get(filename)
        extra_runtime = EXTRA_MANIFESTS.get(filename)

        if (
            runtime_for_manifest is None
            and extra_runtime is None
        ):
            errors.append(
                f"Unsupported manifest filename: {filename}"
            )
            continue

        if not _require_file(
            manifest_path,
            f"Manifest '{filename}'",
            errors,
        ):
            continue

        validated_paths.append(manifest_path)

        if runtime_for_manifest is not None:
            runtime_manifest_paths.append(manifest_path)

        elif extra_runtime is not None:
            extra_manifest_paths.append(manifest_path)

    if not runtime_manifest_paths:
        errors.append(
            "No valid runtime manifest was found. Supporting manifests "
            "alone cannot establish an application's runtime."
        )
        return None, validated_paths

    detection = detect_runtime_from_manifests(
        runtime_manifest_paths
    )

    errors.extend(detection.get("errors", []))
    detected_runtimes = detection.get("detected_runtimes", [])

    if not detected_runtimes:
        errors.append(
            "Unable to determine the application runtime "
            "from its runtime manifests."
        )
        return None, validated_paths

    if len(detected_runtimes) > 1:
        errors.append(
            "Conflicting runtime manifests were found: "
            + ", ".join(detected_runtimes)
        )
        return None, validated_paths

    detected_runtime = detected_runtimes[0]
    if detected_runtime != runtime:
        errors.append(
            f"Declared runtime '{runtime}' does not match "
            f"detected runtime '{detected_runtime}'."
        )

    for extra_manifest in extra_manifest_paths:
        expected_runtime = EXTRA_MANIFESTS.get(extra_manifest.name)
        if expected_runtime != detected_runtime:
            errors.append(
                f"Supporting manifest '{extra_manifest.name}' belongs "
                f"to runtime '{expected_runtime}', but the detected "
                f"runtime is '{detected_runtime}'."
            )

    return runtime_manifest_paths[0], validated_paths


def print_invalid_apps(invalid_apps):
    """Print invalid applications and all their validation errors."""
    for invalid_app in invalid_apps:
        app_name = invalid_app.get("app") or "Unknown application"
        app_dir = invalid_app.get("app_dir")

        _log(
            f"Validation failed for {app_name} ({app_dir}):",
            "ERROR",
        )

        for error in invalid_app.get("errors", []):
            _log(f"  - {error}", "ERROR")

        print(line)


def validate_app(candidate):
    errors = []
    if not isinstance(candidate, dict):
        print_invalid_apps(
            [
                {
                    "app": None,
                    "app_dir": None,
                    "errors": [
                        "Discovery returned an invalid application record."
                    ],
                }
            ]
        )
        return None

    app_dir = candidate.get("app_dir")
    component_dir = candidate.get("component_dir")
    if not isinstance(app_dir, (str, Path)):
        print_invalid_apps(
            [
                {
                    "app": None,
                    "app_dir": None,
                    "errors": [
                        "Discovery record does not contain a valid app_dir."
                    ],
                }
            ]
        )
        return None

    if not isinstance(component_dir, (str, Path)):
        print_invalid_apps(
            [
                {
                    "app": Path(app_dir),
                    "app_dir": Path(app_dir),
                    "errors": [
                        "Discovery record does not contain a valid component_dir."
                    ],
                }
            ]
        )
        return None

    app_dir = Path(app_dir)
    app_name = app_dir.name
    component_dir = Path(component_dir)
    component_name = component_dir.name

    if app_dir != component_dir:
        component_name = "_".join(
            reversed(component_dir.relative_to(app_dir).parts)
        )
        app_name = f"{component_name}_{app_name}"

    _validate_app_directory(app_dir, errors)
    _validate_app_directory(component_dir, errors)
    _validate_discovery_record(candidate, errors)

    ci_file = candidate.get("ci_file")
    config = candidate.get("ci_config")

    if ci_file is None:
        errors.append(
            f"{app_name}: discovery did not provide a ci.yml path."
        )
    else:
        _require_file(
            ci_file,
            "ci.yml",
            errors,
        )

    if not isinstance(config, dict):
        errors.append(
            f"{app_name}: ci.yml configuration is unavailable "
            "or is not a mapping."
        )
        config = {}

    _validate_file_paths_config(config, errors)

    declared_runtime = _validate_runtime_config(
        config,
        errors,
    )

    execution = _validate_execution_config(
        config,
        errors,
    )

    if execution["use_script"]:
        _validate_ci_script_paths(
            ci_scripts=execution["ci_scripts"],
            component_dir=component_dir,
            app_name=app_name,
            errors=errors,
        )

    security_env = _validate_security_env(
        config, errors,
    )
    extra_ci_config = _validate_healthcheck(
        config.get("extra_ci_config", {}),
        errors,
    )

    file_paths = candidate.get("file_paths")
    if not isinstance(file_paths, dict):
        errors.append(
            f"{app_name}: discovery did not provide valid file_paths."
        )
        file_paths = {}

    docker_file = file_paths.get("docker_file")

    _require_file(
        docker_file,
        "Dockerfile",
        errors,
        required=True,
    )

    kubapp_file = file_paths.get("kubapp_file")
    configured_paths = config.get("file_paths", {})
    if not isinstance(configured_paths, dict):
        configured_paths = {}

    kubapp_required = "kubapp_file" in configured_paths
    _require_file(
        kubapp_file,
        "kubapp.yml",
        errors,
        required=kubapp_required,
    )

    secret_file = file_paths.get("secret_file")
    secret_required = "secret_file" in configured_paths

    _require_file(
        secret_file,
        "secret_file",
        errors,
        required=secret_required,
    )

    manifest_paths = file_paths.get("manifest_files", [])
    if declared_runtime is not None:
        primary_manifest, validated_manifest_paths = (
            _validate_manifest_paths(
                manifest_paths,
                declared_runtime,
                errors,
            )
        )
    else:
        primary_manifest = None
        validated_manifest_paths = []
        if isinstance(manifest_paths, list):
            for manifest_path in manifest_paths:
                if not isinstance(manifest_path, (str, Path)):
                    errors.append(
                        f"Invalid manifest path: {manifest_path!r}"
                    )
                    continue

                path = Path(manifest_path)

                if (
                    path.name not in MANIFESTS
                    and path.name not in EXTRA_MANIFESTS
                ):
                    errors.append(
                        f"Unsupported manifest filename: {path.name}"
                    )
                    continue

                _require_file(
                    path,
                    f"Manifest '{path.name}'",
                    errors,
                )

    discovered_runtimes = candidate.get("detected_runtimes", [])
    if not isinstance(discovered_runtimes, list):
        errors.append(
            f"{app_name}: detected_runtimes must be a list."
        )
        discovered_runtimes = []

    if (
        declared_runtime is not None
        and discovered_runtimes
        and declared_runtime not in discovered_runtimes
    ):
        errors.append(
            f"{app_name}: declared runtime '{declared_runtime}' "
            "does not match the runtime recorded during discovery."
        )

    if errors:
        print_invalid_apps(
            [
                {
                    "app": app_name,
                    "app_dir": app_dir,
                    "errors": errors,
                }
            ]
        )
        return None

    validated_app = {
        "app": app_name,
        "app_dir": app_dir,
        "component_dir": component_dir,
        "runtime": declared_runtime,
        "manifest": primary_manifest,
        "manifest_files": validated_manifest_paths,
        "ci_file": Path(ci_file),
        "dockerfile": Path(docker_file),
        "platform_file": (
            Path(kubapp_file)
            if kubapp_file is not None
            else None
        ),
        "secret_file": (
            Path(secret_file)
            if secret_file is not None
            else None
        ),
        "use_script": execution["use_script"],
        "ci_scripts": execution["ci_scripts"],
        "ci_commands": execution["ci_commands"],
        "extra_ci_commands": execution["extra_ci_commands"],
        "extra_ci_config": extra_ci_config,
        "security_env": security_env,
    }

    _log(
        f"Validation passed for {app_name} "
        f"(runtime: {declared_runtime})."
    )

    return validated_app

# Aggregate Validate
def validate_all_apps(candidates=None):
    if candidates is None:
        try:
            candidates = discover_apps()

        except RuntimeError as exc:
            message = str(exc)

            _log(
                f"Application discovery failed: {message}",
                "ERROR",
            )

            return {
                "valid_apps": [],
                "signal": "failure",
            }

    if not isinstance(candidates, list):
        message = "Discovery must return a list of application candidates."

        _log(message, "ERROR")

        return {
            "valid_apps": [],
            "signal": "failure",
        }

    valid_apps = []
    invalid_apps = []

    for candidate in candidates:
        if not isinstance(candidate, dict):
            invalid_apps.append(
                {
                    "app": None,
                    "errors": [
                        "Discovery returned an invalid application record."
                    ],
                }
            )
            continue

        app_dir = candidate.get("app_dir")
        app_name = (
            Path(app_dir).name
            if isinstance(app_dir, (str, Path))
            else None
        )

        validation_errors = []
        if not isinstance(app_dir, (str, Path)):
            validation_errors.append(
                "Discovery record does not contain a valid app_dir."
            )

        else:
            validation_errors.extend(
                candidate.get("discovery_errors", [])
                if isinstance(
                    candidate.get("discovery_errors", []),
                    list,
                )
                else ["Discovery errors are malformed."]
            )

            validation_errors.extend(
                candidate.get("runtime_detection_errors", [])
                if isinstance(
                    candidate.get("runtime_detection_errors", []),
                    list,
                )
                else ["Runtime detection errors are malformed."]
            )

        validated_app = validate_app(candidate)

        if validated_app is not None:
            valid_apps.append(validated_app)
            continue

        if not validation_errors:
            validation_errors.append(
                "Application validation failed. "
                "See the validation log for details."
            )

        invalid_apps.append(
            {
                "app": app_name,
                "app_dir": (
                    Path(app_dir)
                    if isinstance(app_dir, (str, Path))
                    else None
                ),
                "errors": validation_errors,
            }
        )

    if not valid_apps:
        signal = False
    elif invalid_apps:
        signal = False
    else:
        signal = True

    _log(
        "Validation summary: "
        f"{len(valid_apps)} valid app(s), "
        f"{len(invalid_apps)} invalid app(s).",
        "INFO" if signal else "WARNING",
    )

    return {
        "valid_apps": valid_apps,
        "signal": signal,
    }

def validate_apps(candidates=None):
    return validate_all_apps(candidates)
