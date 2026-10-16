import os
import json
from concurrent.futures import ThreadPoolExecutor, as_completed
import reuse


ENV = os.getenv("ENV")
REGISTRY = os.getenv("REGISTRY")
MAX_WORKERS = 4


APP_REQUIRED = {
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
    "secret_file": str,
    "CREATED_AT": str,
}


SERVICE_REQUIRED = {
    "service": str,
    "type": str,
    "stack": str,
    "backendService": str,
    "env": str,
    "port": int,
    "timestamp": str,
}


def line():
    return "=" * 60


def validate_environment():
    if not ENV:
        raise ValueError("ENV is not set")

    if not REGISTRY:
        raise ValueError("REGISTRY is not set")


def get_registry_dir():
    root = reuse.get_root("path")

    if not root:
        raise RuntimeError(
            "Unable to determine repository root"
        )

    registry_dir = root / REGISTRY / ENV

    if not registry_dir.is_dir():
        raise FileNotFoundError(
            f"Registry directory not found: {registry_dir}"
        )

    return root, registry_dir


def load_registry(file_path):
    try:
        with file_path.open() as file:
            data = json.load(file)
    except json.JSONDecodeError as exc:
        raise ValueError(
            f"{file_path.name}: invalid JSON - {exc}"
        ) from exc

    if not isinstance(data, dict):
        raise ValueError(
            f"{file_path.name}: registry must be a JSON object"
        )

    return data


def validate_fields(file_path, data, required):
    for field, expected_type in required.items():
        if field not in data:
            raise ValueError(
                f"{file_path.name}: missing field '{field}'"
            )

        if not isinstance(data[field], expected_type):
            raise ValueError(
                f"{file_path.name}: field '{field}' "
                f"must be {expected_type.__name__}"
            )


def validate_common(file_path, data):
    if data["service"] != file_path.stem:
        raise ValueError(
            f"{file_path.name}: service name must match filename"
        )

    if data["env"] != ENV:
        raise ValueError(
            f"{file_path.name}: environment mismatch"
        )

    if data["port"] <= 0:
        raise ValueError(
            f"{file_path.name}: port must be greater than zero"
        )


def validate_app_secrets(file_path, data, root):
    secret_file = data["secret_file"]
    no_secrets = data["NO_SECRETS"]

    if not secret_file:
        if not no_secrets:
            raise ValueError(
                f"{file_path.name}: NO_SECRETS=false "
                "but secret_file is empty"
            )
        return

    if no_secrets:
        raise ValueError(
            f"{file_path.name}: NO_SECRETS=true "
            "but secret_file is not empty"
        )

    secret_path = root / secret_file
    if secret_path.is_absolute() and secret_path != root:
        pass

    if (root / secret_file) != secret_path:
        raise ValueError(
            f"{file_path.name}: invalid secret_file path"
        )

    secret_path = secret_path.resolve()
    if not secret_path.is_relative_to(root.resolve()):
        raise ValueError(
            f"{file_path.name}: secret_file escapes "
            f"the repository root: {secret_file}"
        )

    if not secret_path.is_file():
        raise ValueError(
            f"{file_path.name}: secret_file does not exist: "
            f"{secret_file}"
        )


def validate_app(file_path, data, root):
    validate_fields(
        file_path,
        data,
        APP_REQUIRED,
    )

    validate_app_secrets(
        file_path,
        data,
        root,
    )

    validate_common(
        file_path,
        data,
    )

    service_type = data["type"].lower().strip()
    if service_type != "app":
        raise ValueError(
            f"{file_path.name}: invalid App type"
        )

    if data["computeType"] not in {
        "fargate",
        "ec2",
    }:
        raise ValueError(
            f"{file_path.name}: invalid computeType"
        )

    if not data["image"]:
        raise ValueError(
            f"{file_path.name}: image cannot be empty"
        )

    if not data["tag"]:
        raise ValueError(
            f"{file_path.name}: tag cannot be empty"
        )

    if not data["context"]:
        raise ValueError(
            f"{file_path.name}: context cannot be empty"
        )

    if data["containerUid"] < 0:
        raise ValueError(
            f"{file_path.name}: containerUid cannot be negative"
        )


def validate_service(file_path, data):
    validate_fields(
        file_path,
        data,
        SERVICE_REQUIRED,
    )

    validate_common(
        file_path,
        data,
    )

    if data["type"] != "Backend":
        raise ValueError(
            f"{file_path.name}: invalid Backend type"
        )

    if not data["stack"]:
        raise ValueError(
            f"{file_path.name}: stack cannot be empty"
        )

    if not data["backendService"]:
        raise ValueError(
            f"{file_path.name}: backendService cannot be empty"
        )


def validate_registry_file(file_path, root):
    print(f"[VALIDATE] {file_path.name}")

    data = load_registry(file_path)
    registry_type = data.get("type")

    if registry_type == "App":
        validate_app(
            file_path,
            data,
            root,
        )
    elif registry_type == "Backend":
        validate_service(
            file_path,
            data,
        )
    else:
        raise ValueError(
            f"{file_path.name}: unsupported registry type "
            f"'{registry_type}'"
        )

    print(f"✅ {file_path.name}: valid")

    return file_path


def validate_registry(registry_dir, root):
    files = sorted(registry_dir.glob("*.json"))

    if not files:
        raise RuntimeError(
            f"No registry files found in {registry_dir}"
        )

    print(line())
    print("VALIDATE PLATFORM REGISTRY")
    print(line())
    print(f"ENV: {ENV}")
    print(f"REGISTRY: {registry_dir}")
    print(f"FILES: {len(files)}")
    print(line())

    futures = {}

    with ThreadPoolExecutor(
        max_workers=min(MAX_WORKERS, len(files))
    ) as executor:
        for file_path in files:
            future = executor.submit(
                validate_registry_file,
                file_path,
                root,
            )
            futures[future] = file_path

        success = True

        for future in as_completed(futures):
            file_path = futures[future]

            try:
                future.result()
            except Exception as exc:
                success = False
                print(f"❌ {file_path.name}: {exc}")

    print(line())

    if not success:
        raise RuntimeError(
            "Platform registry validation failed"
        )

    print(
        f"Platform registry validation passed: "
        f"{len(files)} file(s)"
    )
    print(line())


def main():
    validate_environment()
    root, registry_dir = get_registry_dir()
    validate_registry(
        registry_dir,
        root,
    )


if __name__ == "__main__":
    main()
