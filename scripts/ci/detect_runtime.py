from pathlib import Path
import yaml
import reuse
from java_handler import JavaHandler
from node_handler import NodeHandler
from python_handler import PythonHandler
from variables import EXTRA_MANIFESTS, MANIFESTS


PROJECT_ROOT = Path(reuse.get_root())
DOCKER_DIR = PROJECT_ROOT / "docker"

CI_FILENAME = "ci.yml"
CI_SECRET_FILE = "ci_secrets.yml"
DOCKERFILE_FILE = "Dockerfile"
KUBAPP_FILE = "kubapp.yml"
VALID_APP_SUFFIX = "_app"

HANDLERS = {
    "python": PythonHandler,
    "node": NodeHandler,
    "java": JavaHandler,
}


def get_runtime_handler(runtime):
    """Return the registered handler for a runtime, if supported."""
    return HANDLERS.get(runtime)


def discover_app_roots():
    if not DOCKER_DIR.exists():
        raise RuntimeError(
            f"Docker directory does not exist: {DOCKER_DIR}"
        )

    if not DOCKER_DIR.is_dir():
        raise RuntimeError(
            f"Docker path is not a directory: {DOCKER_DIR}"
        )

    try:
        app_roots = sorted(
            (
                path
                for path in DOCKER_DIR.iterdir()
                if path.is_dir() and path.name.endswith(VALID_APP_SUFFIX)
            ),
            key=lambda path: path.as_posix(),
        )
    except OSError as exc:
        raise RuntimeError(
            f"Unable to discover application roots in {DOCKER_DIR}: {exc}"
        ) from exc

    if not app_roots:
        raise RuntimeError(
            f"No application directories ending in "
            f"'{VALID_APP_SUFFIX}' found in {DOCKER_DIR}"
        )

    return app_roots


def _candidate_record(app_dir, component_dir=None, discovery_errors=None):
    """Create a consistent discovery record for an app component."""
    app_dir = Path(app_dir)
    component_dir = Path(component_dir) if component_dir else app_dir

    return {
        "app_dir": app_dir,
        "component_dir": component_dir,
        "discovery_errors": list(discovery_errors or []),
    }


def _read_ci_config(ci_file):
    ci_file = Path(ci_file)

    try:
        with ci_file.open("r", encoding="utf-8") as file:
            config = yaml.safe_load(file)

    except (OSError, UnicodeError, yaml.YAMLError) as exc:
        return None, [
            f"Unable to read or parse {ci_file}: {exc}"
        ]

    if not isinstance(config, dict):
        return None, [
            f"{ci_file} must contain a YAML mapping."
        ]

    return config, []


def _configured_path_value(value):
    if isinstance(value, str):
        return [value]

    if isinstance(value, list):
        return value

    return []


def _resolve_recorded_path(app_dir, configured_path):
    if not isinstance(configured_path, str) or not configured_path.strip():
        return None, [
            f"Configured file path must be a nonempty string: "
            f"{configured_path!r}"
        ]

    relative_path = Path(configured_path)

    if relative_path.is_absolute():
        return None, [
            f"Absolute file paths are not allowed: {configured_path}"
        ]

    try:
        resolved_app_dir = Path(app_dir).resolve()
        resolved_path = (resolved_app_dir / relative_path).resolve()
        resolved_path.relative_to(resolved_app_dir)

    except (OSError, RuntimeError, ValueError) as exc:
        return None, [
            f"Invalid file path '{configured_path}' for "
            f"{app_dir}: {exc}"
        ]

    return resolved_path, []


def _default_file_path(app_dir, filename):
    """Return the default root-level file path if it exists."""
    path = Path(app_dir) / filename
    return path if path.is_file() else None


def _discover_manifest_paths(app_dir, config, errors):
    file_paths = config.get("file_paths")

    if not isinstance(file_paths, dict):
        file_paths = {}

    if "manifest_files" in file_paths:
        configured_manifests = _configured_path_value(
            file_paths["manifest_files"]
        )

        if not configured_manifests:
            errors.append(
                "file_paths.manifest_files must be a path string "
                "or a nonempty list of path strings."
            )
            return []

        manifest_paths = []

        for configured_path in configured_manifests:
            resolved_path, path_errors = _resolve_recorded_path(
                app_dir,
                configured_path,
            )
            errors.extend(path_errors)
            if resolved_path is not None:
                manifest_paths.append(resolved_path)

        return manifest_paths

    recognized_names = set(MANIFESTS) | set(EXTRA_MANIFESTS)
    manifest_paths = []

    try:
        for path in sorted(
            Path(app_dir).iterdir(),
            key=lambda item: item.name,
        ):
            if path.is_file() and path.name in recognized_names:
                manifest_paths.append(path.resolve())

    except OSError as exc:
        errors.append(
            f"Unable to inspect root-level manifests in "
            f"{app_dir}: {exc}"
        )
    return manifest_paths


def _discover_single_file(
    app_dir,
    config,
    key,
    default_filename,
    errors,
    required=False,
):
    file_paths = config.get("file_paths")

    if not isinstance(file_paths, dict):
        file_paths = {}

    if key in file_paths:
        configured_path = file_paths[key]

        if not isinstance(configured_path, str):
            errors.append(
                f"file_paths.{key} must be a single path string."
            )
            return None

        resolved_path, path_errors = _resolve_recorded_path(
            app_dir,
            configured_path,
        )

        errors.extend(path_errors)
        return resolved_path

    return _default_file_path(app_dir, default_filename)


def _discover_ci_file(app_dir, errors):
    ci_file = Path(app_dir) / CI_FILENAME

    try:
        if not ci_file.is_file():
            errors.append(
                f"Required CI configuration was not found: {ci_file}"
            )
            return ci_file, None

    except OSError as exc:
        errors.append(
            f"Unable to inspect CI configuration {ci_file}: {exc}"
        )
        return ci_file, None

    config, config_errors = _read_ci_config(ci_file)
    errors.extend(config_errors)
    return ci_file, config


def discover_app(app_dir, component_dir=None):
    app_dir = Path(app_dir)
    component_dir = Path(component_dir) if component_dir else app_dir

    record = _candidate_record(
        app_dir,
        component_dir=component_dir,
    )

    app_dir = component_dir
    errors = record["discovery_errors"]
    ci_file, config = _discover_ci_file(app_dir, errors)

    record["ci_file"] = ci_file
    record["ci_config"] = config
    record["file_paths"] = {}

    if config is None:
        record["file_paths"] = {
            "manifest_files": [],
            "docker_file": _default_file_path(app_dir, DOCKERFILE_FILE),
            "kubapp_file": _default_file_path(app_dir, KUBAPP_FILE),
            "secret_file": _default_file_path(app_dir, CI_SECRET_FILE),
        }
        record["detected_runtimes"] = []
        record["runtime_detection_errors"] = []
        return record

    manifest_paths = _discover_manifest_paths(
        app_dir,
        config,
        errors,
    )

    docker_file = _discover_single_file(
        app_dir=app_dir,
        config=config,
        key="docker_file",
        default_filename=DOCKERFILE_FILE,
        errors=errors,
        required=True,
    )

    kubapp_file = _discover_single_file(
        app_dir=app_dir,
        config=config,
        key="kubapp_file",
        default_filename=KUBAPP_FILE,
        errors=errors,
    )

    secret_file = _discover_single_file(
        app_dir=app_dir,
        config=config,
        key="secret_file",
        default_filename=CI_SECRET_FILE,
        errors=errors,
    )

    record["file_paths"] = {
        "manifest_files": manifest_paths,
        "docker_file": docker_file,
        "kubapp_file": kubapp_file,
        "secret_file": secret_file,
    }

    runtime_result = detect_runtime_from_manifests(manifest_paths)

    record["detected_runtimes"] = runtime_result["detected_runtimes"]
    record["runtime_detection_errors"] = runtime_result["errors"]
    return record


def discover_apps():
    app_roots = discover_app_roots()
    candidates = []

    for app_root in app_roots:
        try:
            ci_files = sorted(
                (
                    path
                    for path in app_root.rglob(CI_FILENAME)
                    if path.is_file()
                ),
                key=lambda path: path.as_posix(),
            )

        except OSError as exc:
            candidates.append(
                _candidate_record(
                    app_root,
                    discovery_errors=[
                        f"Unable to search for {CI_FILENAME} "
                        f"under {app_root}: {exc}"
                    ],
                )
            )
            continue

        if not ci_files:
            candidates.append(discover_app(app_root))
            continue

        for ci_file in ci_files:
            candidates.append(
                discover_app(
                    app_dir=app_root,
                    component_dir=ci_file.parent,
                )
            )

    candidates.sort(
        key=lambda candidate: candidate["app_dir"].relative_to(
            DOCKER_DIR
        ).as_posix()
    )

    return candidates


def discover_app_candidates():
    """Backward-compatible alias for app discovery."""
    return discover_apps()


def detect_runtime_from_manifests(manifest_paths):
    detected_runtimes = set()
    errors = []

    for manifest_path in manifest_paths:
        try:
            path = Path(manifest_path)

        except (TypeError, ValueError) as exc:
            errors.append(
                f"Invalid manifest path {manifest_path!r}: {exc}"
            )
            continue

        runtime = MANIFESTS.get(path.name)
        if runtime:
            detected_runtimes.add(runtime)

    return {
        "detected_runtimes": sorted(detected_runtimes),
        "errors": errors,
    }


def detect_app_runtime(app_dir):
    app_dir = Path(app_dir)
    detected_runtimes = set()
    errors = []

    try:
        for path in app_dir.iterdir():
            if not path.is_file():
                continue

            runtime = MANIFESTS.get(path.name)
            if runtime:
                detected_runtimes.add(runtime)

    except OSError as exc:
        errors.append(
            f"Unable to inspect runtime manifests in {app_dir}: {exc}"
        )

    return {
        "detected_runtimes": sorted(detected_runtimes),
        "errors": errors,
    }


def detect_all_runtimes():
    return discover_apps()


def has_runtime(app_dir, runtime):
    """Return whether a root-level runtime manifest identifies a runtime."""
    result = detect_app_runtime(app_dir)
    return (
        not result["errors"]
        and runtime in result["detected_runtimes"]
    )


def detect_apps_by_runtime(runtime):
    """Return discovered candidates whose runtime matches the given value."""
    candidates = discover_apps()
    return [
        candidate
        for candidate in candidates
        if not candidate.get("discovery_errors")
        and not candidate.get("runtime_detection_errors")
        and runtime in candidate.get("detected_runtimes", [])
    ]


def detect_components_by_runtime():
    """Group discovered candidates by their detected runtime."""
    components = {}

    for candidate in discover_apps():
        if candidate.get("discovery_errors"):
            continue

        if candidate.get("runtime_detection_errors"):
            continue

        for runtime in candidate.get("detected_runtimes", []):
            components.setdefault(runtime, []).append(candidate)

    return components
