import os
import json
import shutil
from pathlib import Path

import reuse


REGISTRY = os.getenv("REGISTRY")
ENV = os.getenv("ENV")


def line():
    return "=" * 60


def require_env():
    if not ENV:
        raise ValueError("ENV is not set")

    if not REGISTRY:
        raise ValueError("REGISTRY is not set")


def get_paths():
    root = reuse.get_root("path")
    if not root:
        raise RuntimeError("Unable to determine repository root")

    registry_dir = root / REGISTRY / ENV
    apps_dir = root / "gitops" / "envs" / ENV / "apps"

    return registry_dir, apps_dir


def normalize_service_name(name):
    return (
        name.strip()
        .lower()
        .replace("_", "-")
        .replace(".", "-")
    )


def load_desired_apps(registry_dir):
    if not registry_dir.is_dir():
        raise FileNotFoundError(
            f"Registry directory not found: {registry_dir}"
        )

    desired_apps = set()

    for file_path in registry_dir.glob("*.json"):
        try:
            with file_path.open() as file:
                data = json.load(file)
        except (json.JSONDecodeError, OSError) as exc:
            raise ValueError(
                f"Unable to read registry file: {file_path}"
            ) from exc

        registry_type = str(
            data.get("type", "")
        ).strip().lower()

        if registry_type != "app":
            continue

        service = data.get("service")

        if not isinstance(service, str) or not service.strip():
            raise ValueError(
                f"App registry entry has no valid service: {file_path}"
            )

        desired_apps.add(
            normalize_service_name(service)
        )

    return desired_apps


def reconcile_app_directories(apps_dir, desired_apps):
    if not apps_dir.exists():
        print(
            f"Apps directory does not exist: {apps_dir}"
        )
        return

    if not apps_dir.is_dir():
        raise ValueError(
            f"Apps path is not a directory: {apps_dir}"
        )

    removed = 0

    for app_dir in apps_dir.iterdir():

        # Only application directories are managed.
        if not app_dir.is_dir():
            continue

        app_name = normalize_service_name(
            app_dir.name
        )

        if app_name in desired_apps:
            print(
                f"Keeping GitOps app: {app_dir.name}"
            )
            continue

        print(
            f"Removing stale GitOps app: {app_dir.name}"
        )

        shutil.rmtree(app_dir)
        removed += 1

    return removed


def main():
    require_env()

    registry_dir, apps_dir = get_paths()

    print(line())
    print("RECONCILE GITOPS APPLICATION DIRECTORIES")
    print(line())
    print(f"ENV: {ENV}")
    print(f"REGISTRY: {registry_dir}")
    print(f"APPS: {apps_dir}")
    print(line())

    desired_apps = load_desired_apps(
        registry_dir
    )

    print(
        f"Desired applications: {len(desired_apps)}"
    )

    for app in sorted(desired_apps):
        print(f"  - {app}")

    print(line())

    removed = reconcile_app_directories(
        apps_dir,
        desired_apps,
    )

    print(line())
    print(
        f"Reconciliation complete. "
        f"Removed {removed} stale application(s)."
    )
    print(line())


if __name__ == "__main__":
    main()
