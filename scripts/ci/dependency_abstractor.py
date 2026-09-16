import reuse
import os
import json
from concurrent.futures import ThreadPoolExecutor, as_completed
from variables import CI_COMMANDS, EXTRA_FILES, MANIFESTS
from detect_runtime import (
  detect_valid_apps, detect_app_runtime,
  get_runtime_handler, get_app_ci_commands,)
from app_builder import AppBuilder
from container import ContainerManager

docker_user = os.getenv("DOCKER_USER")
docker_passwd = os.getenv("DOCKER_PASS")
ENV = os.getenv("ENV")
platform_filename = "kubapp.yml"
platform_secrets_filename = "secrets.yml"
runtime_list = set(MANIFESTS.values())
project_root = reuse.get_root()
MAX_WORKERS = 4
ALL_APPS = {}
STORE = {}

def line():
    return "=" * 60

def is_file_okay(path):
    return path.is_file() and bool(path.read_text().strip())

def discover_extra_data(component_dir, runtime):
    extra_data = {}
    for file, file_runtime in EXTRA_FILES.items():
        if file_runtime != runtime:
            continue
        extra = component_dir / file
        if is_file_okay(extra):
            extra_data[file] = extra
    return extra_data

def discover_extra_args(component_dir, runtime):
    all_info = get_app_ci_commands(component_dir, runtime)
    app_commands = all_info.get("ci_commands")
    extra_data = all_info.get("extra_data")
    if not app_commands:
      return CI_COMMANDS.get(runtime, {}), extra_data
    return app_commands, extra_data

def classify_apps():
    apps = detect_valid_apps()
    if not apps:
        return {}

    apps_dict = {}

    for app_dir in apps:
        manifests = detect_app_runtime(app_dir)

        if not manifests:
            print(line())
            print("ATTENTION NEEDED!")
            print(
                f"❌ UNKNOWN app runtime could not be detected. "
                f"Provide a valid manifest at {app_dir}."
            )
            print(line())
            continue

        components = []
        for manifest, runtime in manifests.items():
            component_dir = manifest.parent
            dockerfile = component_dir / "Dockerfile"
            platform_file = component_dir / platform_filename
            secret_file = component_dir / platform_secrets_filename

            if not is_file_okay(manifest):
                continue

            if not is_file_okay(dockerfile):
                dockerfile = False
            if not is_file_okay(platform_file):
                platform_file = False
            if not is_file_okay(secret_file):
                secret_file = False

            ci_cmds, ci_extra = discover_extra_args(component_dir, runtime)
            extra_data = discover_extra_data(component_dir, runtime)

            components.append({
                "manifest": manifest,
                "runtime": runtime,
                "dockerfile": dockerfile,
                "platform_file": platform_file,
                "secret_file": secret_file,
                "extra_data": extra_data,
                "ci_commands": ci_cmds,
                "ci_extra": ci_extra,
            })

        if not components:
            print(line())
            print(
                f"❌ {app_dir.name}: no valid components found. "
                f"App manifest MUST be provided."
            )
            print(line())
            continue

        apps_dict[app_dir] = {
            "app": app_dir.name,
            "components": components,
        }

    return apps_dict

def build_app(app_dir, app_data):
    for component in app_data["components"]:
        manifest = component["manifest"]
        runtime = component["runtime"]
        dockerfile = component["dockerfile"]
        extra_data = component["extra_data"]
        ci_commands = component["ci_commands"]
        extra_ci_data = component["ci_extra"]
        platform_file = component["platform_file"]
        secret_file = component["secret_file"]

        app_name = app_data["app"]
        component_name = manifest.parent.name
        if app_name != component_name:
            app_name = f"{component_name}_{app_name}"

        if runtime not in runtime_list:
            print(
                f"❌ Unsupported runtime '{runtime}' "
                f"for {app_name} with {manifest}"
            )
            continue

        print(line())
        length = len(app_data["components"])
        print(f"[STARTING] {app_name} ({length} component(s))")

        handler_class = get_runtime_handler(runtime)
        if not handler_class:
            continue
        handler = handler_class(
            app_name=app_name,
            manifest=manifest,
            dockerfile=dockerfile,
            extra_data=extra_data,
            ci_commands=ci_commands,
        )

        start = reuse.start_timer()

        handler.install_dependencies()
        handler.lint()
        handler.security_analysis()
        handler.unit_tests()
        image =  handler.build_from_dockerfile()

        duration = reuse.start_timer() - start
        print(f"[{app_name}] Build Duration: {duration:.2f}s")

        container = AppBuilder()
        image = container.tag(image, docker_user)
        validate = container.validate(
          app_dir=app_dir, app_name=app_name, image=image,
          user=docker_user, passwd=docker_passwd,
        )
        authenticate = container.authenticate(docker_user, docker_passwd)
        image = container.push(image)

        container_name = f"{app_name}-test"
        healthcheck = extra_ci_data.get("healthcheck", {})
        app_port = healthcheck.get("app_port")
        host_port = healthcheck.get("host_port")
        endpoint = healthcheck.get("endpoints")[0]
        status = healthcheck.get("expected_status", 200)

        duration = reuse.start_timer() - start
        print(f"[{app_name}] Build + Push Duration: {duration:.2f}s")

        container = ContainerManager()
        container.start_container(image, container_name, host_port, app_port)
        try:
          container.test_container(container_name, host_port, endpoint, status)
        finally:
            container.stop_container(container_name)
            container.remove_container(container_name)

        complete = {
            "image": image,
            "path": str(manifest.parent.relative_to(project_root)),
            "runtime": runtime,
            "extra_ci_data": extra_ci_data,
            "platform_file": str(platform_file) if platform_file else None,
            "secret_file": str(secret_file) if secret_file else None,
        }

        ALL_APPS[app_name] = complete

    return app_dir, True

def start_app_build():
    apps = classify_apps()

    print(line())
    if not apps:
        print("No valid applications found")
        print(line())
        return False

    futures = {}
    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
        for app_dir, app_data in apps.items():
            if not app_data:
                continue

            runtime = app_data["components"][0]["runtime"]
            if runtime not in ["python", "node", "java"]:
                continue

            if not app_data["components"][0]["dockerfile"]:
                print(
                  f"❌ No Build for {app_dir} \n"
                  f"REASON: No Dockerfile Found"
                )
                continue

            extra_data = app_data["components"][0]["ci_extra"]
            healthcheck = extra_data.get("healthcheck", {})

            if not healthcheck:
                print(
                  f"❌ No Build for {app_dir} \n"
                  f"REASON: No healthcheck configuration found for {app_dir}"
                )
                continue

            if ( not healthcheck.get("app_port") or
                not healthcheck.get("host_port")
            ):
                print(
                  f"❌ No Build for {app_dir} \n"
                  f"REASON: one or both host_port and app_port are missing \n"
                  f"ACTINO: Ensure both host_port and "
                  f"app_port are provided in ci.yml"
                )
                continue

            if not healthcheck.get("endpoints")[0]:
                print(
                  f"❌ No Build for {app_dir} \n"
                  f"REASON: No healthcheck endpoint configured for {app_dir} "
                  f"ACTION: provide it in ci.yml"
                )
                continue

            future = executor.submit(build_app, app_dir, app_data)
            futures[future] = app_dir

        success = True
        for future in as_completed(futures):
            app_dir = futures[future]

            try:
                _, result = future.result()
                if result:
                    print(f"✅ {app_dir.name}: completed")
            except Exception as exc:
                success = False
                print(f"❌ {app_dir.name}: failed - {exc}")

    print(line())
    if success:
        print("All applications completed successfully")
    else:
        print("One or more applications failed")
    print(line())
    return success

def save_data():
    if not ALL_APPS:
      return

    ROOT = project_root
    FILE = f"{ROOT}/gitops/state/final_ci_data.json"
    STORE["env"] = ENV
    STORE["apps"] = ALL_APPS
    STORE["timestamp"] = reuse.get_timestamp()
    #print(STORE)
    try:
      with open(FILE, "w") as f:
          json.dump(STORE, f, indent=2, default=str)
    except Exception as e:
      raise RuntimeError(f"ERROR Saving {FILE}: {e}")
    print(f"CI data saved: {FILE}")

if __name__ == "__main__":
    success = start_app_build()
    #print("Running save_data func...................")
    save_data()
    raise SystemExit(0 if success else 1)
