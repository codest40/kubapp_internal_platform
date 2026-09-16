import reuse
from pathlib import Path
from python_handler import PythonHandler
from node_handler import NodeHandler
from java_handler import JavaHandler
from variables import MANIFESTS
import yaml

root = Path(reuse.get_root())
docker_dir = root / "docker"
valid_name = "_app"

HANDLERS = {
    "python": PythonHandler,
    "node": NodeHandler,
    "java": JavaHandler,
}

def get_runtime_handler(runtime):
    return HANDLERS.get(runtime)

def detect_valid_apps():
    if not docker_dir.exists():
        return []
    return [
        app_dir for app_dir in docker_dir.iterdir()
        if app_dir.is_dir() and app_dir.name.endswith(valid_name)
    ]

def detect_app_runtime(app_dir):
    app_data = {}
    for file in app_dir.rglob("*"):
        if not file.is_file():
            continue
        runtime = MANIFESTS.get(file.name)
        if runtime:
            app_data[file] = runtime
    return app_data

def detect_all_runtimes():
    runtimes = set()
    for app_dir in detect_valid_apps():
        runtimes.update(detect_app_runtime(app_dir).values())
    return runtimes

def has_runtime(runtime):
    return runtime in detect_all_runtimes()

def detect_apps_by_runtime(runtime):
    apps = []
    for app_dir in detect_valid_apps():
        manifests = detect_app_runtime(app_dir)
        if runtime in manifests.values():
            apps.append(app_dir)
    return apps

def detect_components_by_runtime(runtime):
    components = []
    for app_dir in detect_valid_apps():
        manifests = detect_app_runtime(app_dir)
        for manifest, detected_runtime in manifests.items():
            if detected_runtime == runtime:
                components.append(manifest)
    return components

def get_app_ci_commands(component_dir, runtime):
    if not component_dir.is_dir():
        raise RuntimeError(f"Invalid component directory: {component_dir}")

    app_dir = component_dir
    while app_dir.parent != docker_dir and app_dir.parent != app_dir:
        app_dir = app_dir.parent

    if app_dir not in detect_valid_apps():
        raise RuntimeError(f"Invalid application directory: {app_dir}")

    manifests = detect_app_runtime(app_dir)
    detected_runtimes = set(manifests.values())

    if runtime not in detected_runtimes:
        raise RuntimeError(
            f"Runtime mismatch for {component_dir}: "
            f"requested '{runtime}', "
            f"detected {sorted(detected_runtimes)}"
        )

    ci_file = component_dir / "ci.yml"
    if not ci_file.is_file() or not ci_file.read_text().strip():
        return {}

    try:
        with ci_file.open() as file:
            ci_data = yaml.safe_load(file)
    except yaml.YAMLError as exc:
        raise RuntimeError(f"Invalid CI configuration: {ci_file}") from exc

    if not isinstance(ci_data, dict):
        raise RuntimeError(f"Invalid CI configuration format: {ci_file}")

    ci_runtime = ci_data.get("runtime")
    if ci_runtime and ci_runtime != runtime:
        raise RuntimeError(
            f"CI runtime mismatch in {ci_file}: "
            f"configured '{ci_runtime}', "
            f"detected '{runtime}'"
        )

    all_info = {}

    ci_commands = ci_data.get("ci_commands", {})
    if not isinstance(ci_commands, dict):
        raise RuntimeError(f"Invalid ci_commands configuration: {ci_file}")
    all_info["ci_commands"] = ci_commands

    ci_extra = ci_data.get("extra_data", {})
    if not isinstance(ci_extra, dict):
        raise RuntimeError(f"Invalid ci_commands configuration: {ci_file}")
    all_info["extra_data"] = ci_extra

    return all_info
