import os
import json
from pathlib import Path
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor, as_completed

import yaml
import reuse


REGISTRY = os.getenv("REGISTRY")
MANIFEST = os.getenv("MANIFEST")
ENV = os.getenv("ENV")
MAX_WORKERS = 4

def line():
    return "=" * 60

def require_env():
    if not ENV:
        raise ValueError("ENV is not set")

    if not MANIFEST:
        raise ValueError("MANIFEST is not set")

    if not REGISTRY:
        raise ValueError("REGISTRY is not set")


def get_paths():
    root = reuse.get_root()
    if not root:
        raise RuntimeError("Unable to determine repository root")

    manifest = root / MANIFEST / "final_ci_data.json"
    registry = root / REGISTRY / ENV

    return root, manifest, registry


def load_ci_data(manifest):
    if not manifest.is_file():
        raise FileNotFoundError(
            f"CI manifest not found: {manifest}"
        )

    if manifest.stat().st_size == 0:
        raise ValueError(
            f"CI manifest is empty: {manifest}"
        )

    try:
        with manifest.open() as file:
            data = json.load(file)
    except json.JSONDecodeError as exc:
        raise ValueError(
            f"Invalid CI manifest JSON: {manifest}"
        ) from exc

    if not isinstance(data, dict):
        raise ValueError("CI manifest must contain an object")

    if data.get("env") != ENV:
        raise ValueError(
            f"Environment mismatch: "
            f"workflow={ENV}, manifest={data.get('env')}"
        )

    apps = data.get("apps")

    if not isinstance(apps, dict) or not apps:
        raise ValueError("CI manifest contains no applications")

    return apps

def normalize_service_name(name):
    name = name.strip().lower()
    if "_" in name:
        name = name.replace("_", "-")
    if "." in name:
        name = name.replace(".", "-")
    return name

def validate_ci_app(app_name, app):
    if not isinstance(app, dict):
        raise ValueError(
            f"{app_name}: CI application data must be an object"
        )

    required = [
        "image",
        "path",
        "runtime",
        "extra_ci_data",
        "platform_file",
        "secret_file",
    ]

    for field in required:
        if field not in app:
            raise ValueError(
                f"{app_name}: missing CI field '{field}'"
            )

    if not app["image"]:
        raise ValueError(
            f"{app_name}: image is empty"
        )

    if not app["path"]:
        raise ValueError(
            f"{app_name}: path is empty"
        )

    if not app["runtime"]:
        raise ValueError(
            f"{app_name}: runtime is empty"
        )

    if not isinstance(app["extra_ci_data"], dict):
        raise ValueError(
            f"{app_name}: extra_ci_data must be an object"
        )


def load_platform_config(app_name, platform_file):
    if platform_file is None:
        return {}

    path = Path(platform_file)

    if not path.is_file():
        raise FileNotFoundError(
            f"{app_name}: platform_file does not exist: {path}"
        )

    if path.stat().st_size == 0:
        raise ValueError(
            f"{app_name}: platform_file is empty: {path}"
        )

    try:
        with path.open() as file:
            data = yaml.safe_load(file)
    except yaml.YAMLError as exc:
        raise ValueError(
            f"{app_name}: invalid kubapp.yml: {path}"
        ) from exc

    if data is None:
        return {}

    if not isinstance(data, dict):
        raise ValueError(
            f"{app_name}: kubapp.yml must contain an object"
        )
    return data

def get_image_data(image):
    image = image.strip()

    last_slash = image.rfind("/")
    last_colon = image.rfind(":")

    if last_colon <= last_slash:
        raise ValueError(
            f"Invalid tagged image: {image}"
        )

    repository = image[:last_colon]
    tag = image[last_colon + 1:]

    if not repository or not tag:
        raise ValueError(
            f"Invalid image: {image}"
        )

    return repository, tag


def get_healthcheck(app):
    healthcheck = app["extra_ci_data"].get(
        "healthcheck",
        {}
    )

    if not isinstance(healthcheck, dict):
        raise ValueError(
            "healthcheck must be an object"
        )

    return healthcheck


def get_port(app, platform):
    platform_app = platform.get("app", {})

    if "port" in platform_app:
        return platform_app["port"]

    healthcheck = get_healthcheck(app)

    if "app_port" in healthcheck:
        return healthcheck["app_port"]

    return 80


def get_health_path(app, platform):
    platform_app = platform.get("app", {})

    if platform_app.get("healthPath"):
        return platform_app["healthPath"]

    endpoints = get_healthcheck(app).get(
        "endpoints",
        []
    )

    if endpoints:
        return endpoints[0]

    return "/health"


def get_volume_data(app_name, platform):
    storage = platform.get("storage", {})

    volumes = storage.get("volumes", [])

    if volumes:
        volume_name = volumes[0].get("name")
    else:
        volume_name = None

    if not volume_name:
        volume_name = f"{app_name}-vol"

    volume_name = normalize_service_name(volume_name)
    mounts = storage.get("volumeMounts", [])

    if mounts:
        mount = mounts[0]

        mount_volume = mount.get(
            "name",
            volume_name,
        )
        mount_volume = normalize_service_name(mount_volume)
        mount_path = mount.get(
            "mountPath",
            "/tmp",
        )
    else:
        mount_volume = volume_name
        mount_path = "/tmp"

    return volume_name, mount_volume, mount_path


def get_no_vars(platform):
    runtime = platform.get("runtime", {})
    variables = runtime.get("env")

    if variables is None:
        return True

    if not isinstance(variables, dict):
        raise ValueError(
            "runtime.env must be an object"
        )
    return not bool(variables)


def get_no_secrets(app):
    return app["secret_file"] is None


def construct_registry(app_name, app, platform):
    repository, tag = get_image_data(
        app["image"]
    )

    service = platform.get("service", {})
    application = platform.get("app", {})
    deploy = platform.get("deploy", {})
    features = platform.get("features", {})

    if not isinstance(service, dict):
        raise ValueError(
            f"{app_name}: service must be an object"
        )

    if not isinstance(application, dict):
        raise ValueError(
            f"{app_name}: app must be an object"
        )

    if not isinstance(deploy, dict):
        raise ValueError(
            f"{app_name}: deploy must be an object"
        )

    if not isinstance(features, dict):
        raise ValueError(
            f"{app_name}: features must be an object"
        )

    app_env = deploy.get("env", ENV)
    if app_env != ENV:
        raise ValueError(
            f"{app_name}: platform env={app_env} "
            f"does not match ENV={ENV}"
        )

    canonical_service = normalize_service_name(
      service.get("name", app_name)
    )

    volume_name, mount_volume, mount_path = (
        get_volume_data(canonical_service, platform)
    )

    service_monitor = features.get(
        "serviceMonitor",
        {}
    )

    top_volume = features.get(
        "topVolume",
        {}
    )

    tmp = features.get(
        "tmp",
        {}
    )

    registry = {
        "service": canonical_service,
        "type": "App",
        "runtime": app["runtime"],
        "computeType": service.get(
            "compute",
            "fargate",
        ),
        "context": app["path"],
        "image": repository,
        "tag": tag,
        "registry": "docker.io",
        "namespace": ENV,
        "env": app_env,
        "port": get_port(
            app,
            platform,
        ),
        "containerUid": deploy.get(
            "containerUid",
            10000,
        ),
        "basePath": application.get(
            "basePath",
            "/",
        ),
        "healthPath": get_health_path(
            app,
            platform,
        ),
        "livePath": application.get(
            "livePath",
            "/health",
        ),
        "svc_monitor_enabled": service_monitor.get(
            "enabled",
            False,
        ),
        "volumes_enabled": top_volume.get(
            "enabled",
            False,
        ),
        "tmp_enabled": tmp.get(
            "enabled",
            False,
        ),
        "tmp_volume": volume_name,
        "mount_vol": mount_volume,
        "mount_path": mount_path,
        "NO_VARS": get_no_vars(
            platform
        ),
        "NO_SECRETS": get_no_secrets(
            app
        ),
        "CREATED_AT": datetime.now().strftime(
            "%Y-%m-%d_%H-%M-%S"
        ),
    }
    return registry


def validate_registry(app_name, registry):
    required = {
        "service": str,
        "type": str,
        "computeType": str,
        "context": str,
        "image": str,
        "tag": str,
        "registry": str,
        "namespace": str,
        "env": str,
        "port": int,
        "containerUid": int,
        "basePath": str,
        "healthPath": str,
        "livePath": str,
        "svc_monitor_enabled": bool,
        "volumes_enabled": bool,
        "tmp_enabled": bool,
        "tmp_volume": str,
        "mount_vol": str,
        "mount_path": str,
        "NO_VARS": bool,
        "NO_SECRETS": bool,
        "CREATED_AT": str,
    }

    for field, expected_type in required.items():
        if field not in registry:
            raise ValueError(
                f"{app_name}: missing registry field '{field}'"
            )

        if not isinstance(
            registry[field],
            expected_type,
        ):
            raise ValueError(
                f"{app_name}: registry field '{field}' "
                f"must be {expected_type.__name__}"
            )

    if registry["type"] != "App":
        raise ValueError(
            f"{app_name}: registry type must be App"
        )

    if registry["env"] != ENV:
        raise ValueError(
            f"{app_name}: registry environment mismatch"
        )

    if registry["port"] <= 0:
        raise ValueError(
            f"{app_name}: port must be greater than zero"
        )

    if registry["containerUid"] < 0:
        raise ValueError(
            f"{app_name}: containerUid cannot be negative"
        )


def write_registry(registry_dir, app_name, registry):
    file_path = registry_dir / f"{registry['service']}.json"

    with file_path.open("w") as file:
        json.dump(
            registry,
            file,
            indent=2,
        )
        file.write("\n")

    if not file_path.is_file():
        raise RuntimeError(
            f"{app_name}: registry file was not created"
        )

    return file_path


def build_one_app(root, registry_dir, app_name, app):
    print(line())
    print(f"[PLATFORM] Processing {app_name}")

    validate_ci_app(
        app_name,
        app,
    )

    print(
        f"[{app_name}] CI data validated"
    )

    platform = load_platform_config(
        app_name,
        app["platform_file"],
    )

    if app["platform_file"]:
        print(
            f"[{app_name}] kubapp.yml loaded"
        )
    else:
        print(
            f"[{app_name}] No kubapp.yml - using defaults"
        )

    if app["secret_file"]:
        print(
            f"[{app_name}] secrets.yml detected"
        )
    else:
        print(
            f"[{app_name}] No secrets.yml detected"
        )

    registry = construct_registry(
        app_name,
        app,
        platform,
    )

    validate_registry(
        app_name,
        registry,
    )

    print(
        f"[{app_name}] Registry validated"
    )

    file_path = write_registry(
        registry_dir,
        app_name,
        registry,
    )

    print(
        f"[{app_name}] Registry written: {file_path}"
    )

    return app_name, file_path


def main():
    require_env()

    root, manifest, registry_dir = get_paths()

    print(line())
    print("BUILD APPLICATION REGISTRY")
    print(line())
    print(f"ENV: {ENV}")
    print(f"MANIFEST: {manifest}")
    print(f"REGISTRY: {registry_dir}")
    print(line())

    apps = load_ci_data(manifest)

    registry_dir.mkdir(
        parents=True,
        exist_ok=True,
    )

    futures = {}

    with ThreadPoolExecutor(
        max_workers=min(
            MAX_WORKERS,
            len(apps),
        )
    ) as executor:

        for app_name, app in apps.items():
            future = executor.submit(
                build_one_app,
                root,
                registry_dir,
                app_name,
                app,
            )

            futures[future] = app_name

        success = True

        for future in as_completed(futures):
            app_name = futures[future]

            try:
                future.result()
                print(
                    f"✅ {app_name}: platform registry completed"
                )
            except Exception as exc:
                success = False
                print(
                    f"❌ {app_name}: platform registry failed - {exc}"
                )

    print(line())

    if not success:
        raise RuntimeError(
            "One or more application registries failed"
        )

    print(
        f"Application registry build completed: "
        f"{len(apps)} application(s)"
    )

    print(line())


if __name__ == "__main__":
    main()
