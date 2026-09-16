import os
import json
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor, as_completed

import reuse


ENV = os.getenv("ENV")
REGISTRY = os.getenv("REGISTRY")

MAX_WORKERS = 4


SERVICES = {
    "grafana": {
        "type": "Backend",
        "stack": "monitoring",
        "backendService": "kube-prometheus-stack-grafana",
        "port": 3000,
    },
    "prometheus": {
        "type": "Backend",
        "stack": "monitoring",
        "backendService": "kube-prometheus-stack-prometheus",
        "port": 9090,
    },
    "alertmanager": {
        "type": "Backend",
        "stack": "monitoring",
        "backendService": "kube-prometheus-stack-alertmanager",
        "port": 9093,
    },
    "argocd": {
        "type": "Backend",
        "stack": "argocd",
        "backendService": "argocd-server",
        "port": 8080,
    },
}


def line():
    return "=" * 60


def validate_environment():
    if not ENV:
        raise ValueError("ENV is not set")

    if not REGISTRY:
        raise ValueError("REGISTRY is not set")


def get_registry_dir():
    root = reuse.get_root()

    if not root:
        raise RuntimeError(
            "Unable to determine repository root"
        )

    registry_dir = root / REGISTRY / ENV

    registry_dir.mkdir(
        parents=True,
        exist_ok=True,
    )

    return registry_dir


def construct_service(service_name, service_data):
    if not isinstance(service_data, dict):
        raise ValueError(
            f"{service_name}: service definition must be an object"
        )

    required = [
        "type",
        "stack",
        "backendService",
        "port",
    ]

    for field in required:
        if field not in service_data:
            raise ValueError(
                f"{service_name}: missing service field '{field}'"
            )

    registry = {
        "service": service_name,
        "type": service_data["type"],
        "stack": service_data["stack"],
        "backendService": service_data["backendService"],
        "env": ENV,
        "port": service_data["port"],
        "timestamp": datetime.now().strftime(
            "%Y-%m-%d_%H-%M-%S"
        ),
    }

    return registry


def validate_service(service_name, registry):
    required = {
        "service": str,
        "type": str,
        "stack": str,
        "backendService": str,
        "env": str,
        "port": int,
        "timestamp": str,
    }

    for field, expected_type in required.items():
        if field not in registry:
            raise ValueError(
                f"{service_name}: missing registry field '{field}'"
            )

        if not isinstance(
            registry[field],
            expected_type,
        ):
            raise ValueError(
                f"{service_name}: field '{field}' "
                f"must be {expected_type.__name__}"
            )

    if registry["service"] != service_name:
        raise ValueError(
            f"{service_name}: service name mismatch"
        )

    if registry["type"] != "Backend":
        raise ValueError(
            f"{service_name}: invalid service type"
        )

    if registry["env"] != ENV:
        raise ValueError(
            f"{service_name}: environment mismatch"
        )

    if registry["port"] <= 0:
        raise ValueError(
            f"{service_name}: port must be greater than zero"
        )


def write_service(registry_dir, service_name, registry):
    file_path = registry_dir / f"{service_name}.json"

    with file_path.open("w") as file:
        json.dump(
            registry,
            file,
            indent=2,
        )
        file.write("\n")

    if not file_path.is_file():
        raise RuntimeError(
            f"{service_name}: registry file was not created"
        )

    return file_path


def build_one_service(
    registry_dir,
    service_name,
    service_data,
):
    print(line())
    print(f"[PLATFORM] Processing service: {service_name}")

    registry = construct_service(
        service_name,
        service_data,
    )

    validate_service(
        service_name,
        registry,
    )

    print(
        f"[{service_name}] Registry validated"
    )

    file_path = write_service(
        registry_dir,
        service_name,
        registry,
    )

    print(
        f"[{service_name}] Registry written: {file_path}"
    )

    return service_name, file_path


def main():
    validate_environment()

    registry_dir = get_registry_dir()

    if not SERVICES:
        raise RuntimeError(
            "No platform services configured"
        )

    print(line())
    print("BUILD PLATFORM SERVICE REGISTRY")
    print(line())
    print(f"ENV: {ENV}")
    print(f"REGISTRY: {registry_dir}")
    print(f"SERVICES: {len(SERVICES)}")
    print(line())

    futures = {}

    with ThreadPoolExecutor(
        max_workers=min(
            MAX_WORKERS,
            len(SERVICES),
        )
    ) as executor:

        for service_name, service_data in SERVICES.items():
            future = executor.submit(
                build_one_service,
                registry_dir,
                service_name,
                service_data,
            )

            futures[future] = service_name

        success = True

        for future in as_completed(futures):
            service_name = futures[future]

            try:
                future.result()
                print(
                    f"✅ {service_name}: completed"
                )
            except Exception as exc:
                success = False
                print(
                    f"❌ {service_name}: failed - {exc}"
                )

    print(line())

    if not success:
        raise RuntimeError(
            "One or more platform services failed"
        )

    print(
        f"Platform service registry completed successfully: "
        f"{len(SERVICES)} service(s)"
    )

    print(line())


if __name__ == "__main__":
    main()
