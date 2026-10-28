import json
import os
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from pathlib import Path

import reuse
from app_validator import ValidateApp
from container import ContainerManager
from detect_runtime import get_runtime_handler
from validate import validate_apps
from manage_env import prepare_component_environment
from check_podman_capability import log_podman_capability_assessment
from variables import CI_COMMANDS, EXTRA_MANIFESTS, MANIFESTS, RUNTIME_IMAGES


DOCKER_USER = os.getenv("DOCKER_USER")
DOCKER_PASS = os.getenv("DOCKER_PASS")
ENV = os.getenv("ENV", "dev")
STRICT_MODE = os.getenv("STRICT_MODE", "true").strip().lower() == "true"
FAIL_MODE = os.getenv("FAIL_MODE", "true").strip().lower() == "true"


PROJECT_ROOT = Path(reuse.get_root())
RUNTIME_LIST = set(MANIFESTS.values())
MAX_WORKERS = 4

ALL_APPS = {}
STORE = {}


def is_file_okay(path):
    try:
        path = Path(path)
        if not path.is_file():
            return False
        return bool(path.read_text(encoding="utf-8").strip())
    except (OSError, UnicodeError):
        return False


def discover_extra_manifests(manifest_files, runtime):
    extra_manifests = []
    for manifest_file in manifest_files:
        manifest_path = Path(manifest_file)
        for filename, extra_runtime in EXTRA_MANIFESTS.items():
            if extra_runtime != runtime:
                continue
            if filename != manifest_path.name:
                continue
            if is_file_okay(manifest_path):
                extra_manifests.append(manifest_path)
            break
    return extra_manifests

def classify_apps(validated_apps):
    classified_apps = {}

    if not validated_apps:
        print("No validated applications were provided for classification.")
        return classified_apps

    for app in validated_apps:
        app_name = app["app"]
        app_dir = Path(app["app_dir"]).resolve()
        component_dir = Path(
            app.get("component_dir", app_dir)
        ).resolve()

        extra_manifests = discover_extra_manifests(
            app.get("manifest_files", []), app["runtime"],
        )

        component = {
            "app": app_name,
            "app_dir": app_dir,
            "component_dir": component_dir,
            "manifest": app["manifest"],
            "manifest_files": app.get("manifest_files", []),
            "extra_manifests": extra_manifests,
            "runtime": app["runtime"],
            "dockerfile": app["dockerfile"],
            "platform_file": app.get("platform_file"),
            "secret_file": app.get("secret_file"),
            "use_script": app.get("use_script", False),
            "ci_scripts": app.get("ci_scripts", []),
            "ci_commands": ( app.get("ci_commands")
                or CI_COMMANDS.get(app["runtime"], {})),
            "extra_ci_commands": app.get("extra_ci_commands", {}),
            "extra_ci_config": app.get("extra_ci_config", {}),
            "security_env": app.get("security_env", []),
        }

        classified_apps.setdefault(app_dir, []).append(component)
    return classified_apps

def build_component(app_dir, component):
    app_dir = Path(app_dir).resolve()
    app_name = component["app"]
    component_dir = Path(component["component_dir"]).resolve()

    try:
        runtime = component["runtime"]
        if runtime not in RUNTIME_LIST:
            raise RuntimeError(
                f"Unsupported runtime for {app_name}: {runtime}"
            )
        execution_image = RUNTIME_IMAGES.get(runtime)
        if not execution_image:
            raise RuntimeError(
              f"No execution image configured for runtime: {runtime}"
        )
        component_environment = prepare_component_environment(
                app_name=app_name,
                component_dir=component_dir,
                secret_file=component["secret_file"],
                security_env=component["security_env"],
                execution_image=execution_image,
                runtime=runtime,
        )

        handler_class = get_runtime_handler(runtime)
        if handler_class is None:
            raise RuntimeError(
                f"No runtime handler found for {runtime}"
            )

        handler = handler_class(
            app_name=app_name,
            component_dir=component_dir,
            parent_dir=app_dir,
            runtime=runtime,
            manifest=component["manifest"],
            extra_manifests=component["extra_manifests"],
            dockerfile=component["dockerfile"],
            ci_commands=component["ci_commands"],
            extra_ci_commands=component["extra_ci_commands"],
            extra_ci_config=component["extra_ci_config"],
            security_env = component["security_env"],
            component_environment=component_environment,
        )

        print(
            f"[{app_name}] Starting CI "
            f"for runtime={runtime}, component={component_dir}"
        )

        image = handler.run_ci(
            use_script=component["use_script"],
            ci_scripts=component["ci_scripts"],
        )

        if not image:
            raise RuntimeError(
                f"CI checks or image build failed for {app_name}"
            )

        validator = ValidateApp(
            app_name=app_name,
            app_dir=component_dir,
            runtime=runtime,
            manifest=component["manifest"],
            dockerfile=component["dockerfile"],
        )

        image_tag = validator.tag(image, DOCKER_USER)
        validator.validate_image(image_tag)

        extra_ci_config = component["extra_ci_config"]
        healthcheck = extra_ci_config["healthcheck"]
        app_port = healthcheck["app_port"]
        host_port = healthcheck["host_port"]
        endpoints = healthcheck["endpoints"]
        expected_status = healthcheck.get("expected_status", 200)

        container_manager = ContainerManager()
        container = container_manager.start_container(
            image=image_tag,
            container_name=app_name,
            app_port=app_port,
            host_port=host_port,
        )

        try:
            health_success = container_manager.test_container(
                container=container,
                host_port=host_port,
                endpoints=endpoints,
                expected_status=expected_status,
            )

            if not health_success:
                raise RuntimeError(
                    f"Health checks failed for {app_name}"
                )

        finally:
            try:
                container_manager.stop_container(container)
            finally:
                container_manager.remove_container(container)

        validator.authenticate(username=DOCKER_USER, password=DOCKER_PASS)
        validator.push(image_tag)

        app_result = {
            "image": str(image_tag),
            "path": str(component_dir.relative_to(PROJECT_ROOT)),
            "runtime": runtime,
            "extra_ci_data": extra_ci_config,
            "platform_file": (
                str(component["platform_file"])
                if component["platform_file"]
                else None
            ),
        }

        print(f"[{app_name}] CI completed successfully")
        return app_name, True, app_result

    except Exception as exc:
        print(
            f"[{app_name}] CI failed "
            f"for component {component_dir}: {exc}"
        )
        return app_name, False, None


def start_app_build(classified_apps):
    signal = True
    failed_apps = []
    tasks = [
        (app_dir, component)
        for app_dir, components in classified_apps.items()
        for component in components
    ]

    if not tasks:
        print("No components available for CI execution")
        return False

    print(
        f"Starting CI for {len(tasks)} components "
        f"with a maximum of {MAX_WORKERS} concurrent workers"
    )

    #MAX_WORKERS = len(tasks)
    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
        futures = {
            executor.submit(build_component, app_dir, component): (
                app_dir,
                component,
            )
            for app_dir, component in tasks
        }

        for future in as_completed(futures):
            app_dir, component = futures[future]

            try:
                app_name, success, app_result = future.result()
            except Exception as exc:
                app_name = component.get("app", "<unknown>")
                print(
                    f"[{app_name}] Unexpected worker failure "
                    f"for root {app_dir}: {exc}"
                )
                failed_apps.append(app_name)
                signal = False
                continue

            if success:
                ALL_APPS[app_name] = app_result
                print(f"[{app_name}] Result: SUCCESS")
            else:
                failed_apps.append(app_name)
                signal = False
                print(f"[{app_name}] Result: FAILED")

    successful_components = len(ALL_APPS)

    print(
        f"Component CI execution finished. "
        f"Successful component results recorded: "
        f"{successful_components}/{len(tasks)}"
    )

    if failed_apps:
        reuse.BIG_LINE("#")
        print("Failed applications:")
        for app_name in failed_apps:
            print(f"  - {app_name}")
        reuse.BIG_LINE("#")

    return signal


def validation_gate(validation_result):
    if not isinstance(validation_result, dict):
        print("Validation failed: the validator returned an invalid result.")
        return False

    valid_apps = validation_result.get("valid_apps")
    signal = validation_result.get("signal")
    if not isinstance(valid_apps, list):
        print("Validation failed: valid_apps must be a list.")
        return False

    if not valid_apps:
        print("Validation failed: no valid applications are available.")
        return False

    if STRICT_MODE and not signal:
        print(
            "Strict mode is enabled. Validation did not succeed completely; "
            "the build stage will not start."
        )
        return False

    if not STRICT_MODE and not signal:
        print(
            "Strict mode is disabled. Continuing with validated applications."
        )
    return True


def save_data():
    if not ALL_APPS:
        print("No successful application builds to save.")
        return False

    output_file = (
        PROJECT_ROOT
        / "gitops"
        / "state"
        / "final_ci_data.json"
    )

    payload = {
        "env": ENV,
        "apps": ALL_APPS,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }

    try:
        output_file.parent.mkdir(
            parents=True,
            exist_ok=True,
        )

        temporary_file = output_file.with_suffix(
            output_file.suffix + ".tmp"
        )

        temporary_file.write_text(
            json.dumps(payload, indent=2),
            encoding="utf-8",
        )

        temporary_file.replace(output_file)

        print(f"Final CI data saved to {output_file}")
        return True

    except (OSError, TypeError, ValueError) as exc:
        print(f"Failed to save final CI data: {exc}")
        return False


def main():
    """
    Orchestrate validation, classification, builds, and final data saving.
    """
    ALL_APPS.clear()

    try:
        log_podman_capability_assessment()
        validation_result = validate_apps()
        if not validation_gate(validation_result):
            return 1

        valid_apps = validation_result["valid_apps"]
        classified_apps = classify_apps(valid_apps)
        if not classified_apps:
            print("No applications remain after classification.")
            return 1

        build_signal = start_app_build(classified_apps)

        if not build_signal and FAIL_MODE:
            print("One or more application builds failed.")
            return 1

        if not save_data():
            return 1
        print("CI workflow completed successfully.")
        return 0

    except Exception as exc:
        print(f"CI workflow failed: {exc}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
