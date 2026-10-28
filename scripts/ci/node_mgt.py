"""Prepare isolated npm dependencies for KUBAPP CI."""

from __future__ import annotations

import json
import os
import re
import shlex
import shutil
import subprocess
import tempfile
import textwrap
from pathlib import Path
from variables import RUNTIME_DEPENDENCY_CONFIG


class NodeStagingError(RuntimeError):
    """Raised when Node.js dependency preparation fails."""


_CONTAINER_COMPONENT = "/workspace"
_CONTAINER_DEPENDENCIES = "/opt/kubapp-dependencies"
_CONTAINER_BUILD = "/tmp/kubapp-node-build"


def _get_node_dependency_config() -> dict[str, str]:
    """Return and validate the configured Node.js dependency paths."""

    config = RUNTIME_DEPENDENCY_CONFIG.get("node")

    if not isinstance(config, dict):
        raise NodeStagingError(
            "RUNTIME_DEPENDENCY_CONFIG has no valid Node.js configuration."
        )

    required_keys = (
        "dependency_path",
        "executable_path",
        "required_path",
    )

    validated: dict[str, str] = {}

    for key in required_keys:
        value = config.get(key)

        if not isinstance(value, str) or not value.strip():
            raise NodeStagingError(
                f"Invalid Node.js dependency configuration: {key}."
            )

        relative_path = Path(value)

        if relative_path.is_absolute() or ".." in relative_path.parts:
            raise NodeStagingError(
                f"Node.js configuration {key!r} must be a safe relative path."
            )

        validated[key] = value

    return validated


def _podman_path() -> str:
    """Resolve Podman from supported absolute paths."""

    for candidate in ("/usr/local/bin/podman", "/usr/bin/podman"):
        path = Path(candidate)

        if path.is_file() and path.stat().st_mode & 0o111:
            return str(path)

    raise NodeStagingError(
        "Podman executable was not found in the supported paths."
    )


def _run_podman(
    command: list[str],
    *,
    label: str,
) -> subprocess.CompletedProcess[str]:
    """Run a Podman operation and retain useful failure output."""

    try:
        result = subprocess.run(
            command,
            check=False,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except OSError as exc:
        raise NodeStagingError(
            f"{label}: could not execute Podman: {exc}"
        ) from exc

    if result.returncode != 0:
        details = "\n".join(
            part
            for part in (result.stdout, result.stderr)
            if part
        ).strip()

        raise NodeStagingError(
            f"{label} failed with exit code {result.returncode}."
            + (f"\n{details}" if details else "")
        )

    if result.stdout:
        print(result.stdout, end="")

    if result.stderr:
        print(result.stderr, end="")

    return result


def _ensure_image_available(podman: str, image: str) -> None:
    """Ensure the configured Node.js execution image is available."""

    try:
        result = subprocess.run(
            [podman, "image", "exists", image],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except OSError as exc:
        raise NodeStagingError(
            f"Could not check Node.js execution image {image!r}: {exc}"
        ) from exc

    if result.returncode == 0:
        return

    _run_podman(
        [podman, "pull", image],
        label=f"Pulling Node.js execution image {image}",
    )


def _publish_sbom(sbom_path: Path, app_name: str) -> Path:
    """Validate and atomically publish the generated SBOM."""

    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", app_name):
        raise NodeStagingError(
            f"Invalid application name for SBOM publication: {app_name!r}"
        )

    try:
        sbom = json.loads(sbom_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise NodeStagingError(
            f"Cannot read generated SBOM {sbom_path}: {exc}"
        ) from exc

    if not isinstance(sbom, dict):
        raise NodeStagingError(
            "Generated SBOM must be a JSON object."
        )

    app_section = sbom.get("app_section")
    kubapp_data = sbom.get("kubapp_data")

    kubapp_section = (
        kubapp_data.get("section")
        if isinstance(kubapp_data, dict)
        else None
    )

    if not isinstance(app_section, dict):
        raise NodeStagingError(
            "SBOM is missing app_section."
        )

    if app_section.get("app_name") != app_name:
        raise NodeStagingError(
            f"SBOM application mismatch: expected {app_name!r}, "
            f"got {app_section.get('app_name')!r}."
        )

    if app_section.get("runtime") != "node":
        raise NodeStagingError(
            "SBOM runtime must be 'node'."
        )

    if not isinstance(app_section.get("packages"), dict):
        raise NodeStagingError(
            "SBOM app_section.packages must be an object."
        )

    if not app_section["packages"]:
        raise NodeStagingError(
            "SBOM application package inventory must not be empty."
        )

    if not isinstance(kubapp_section, dict):
        raise NodeStagingError(
            "SBOM is missing kubapp_data.section."
        )

    tools = kubapp_section.get("tools")

    if not isinstance(tools, dict) or not tools.get("npm-audit"):
        raise NodeStagingError(
            "SBOM is missing npm-audit tool metadata."
        )

    if not isinstance(kubapp_section.get("packages"), dict):
        raise NodeStagingError(
            "SBOM kubapp_data.section.packages must be an object."
        )

    repo_root = Path(__file__).resolve().parents[2]
    sbom_dir = repo_root / "gitops" / "state" / "sbom"
    target = sbom_dir / f"{app_name}.json"

    try:
        sbom_dir.mkdir(parents=True, exist_ok=True)

        fd, temp_name = tempfile.mkstemp(
            prefix=f".{app_name}.",
            suffix=".tmp",
            dir=sbom_dir,
        )

        temp_path = Path(temp_name)

        try:
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                json.dump(sbom, handle, indent=2, sort_keys=True)
                handle.write("\n")
                handle.flush()
                os.fsync(handle.fileno())

            os.replace(temp_path, target)

        finally:
            temp_path.unlink(missing_ok=True)

    except OSError as exc:
        raise NodeStagingError(
            f"Failed to publish SBOM for {app_name}: {exc}"
        ) from exc

    print(f"[node_mgt] Published SBOM: {target}")

    return target


def _build_install_script(app_name: str) -> str:
    """Build the isolated npm installation, audit, and SBOM script."""

    build_dir = _CONTAINER_BUILD
    dependency_dir = _CONTAINER_DEPENDENCIES
    sbom_path = f"{dependency_dir}/sbom.json"

    sbom_script = textwrap.dedent(
        f"""
        const fs = require("node:fs");
        const path = require("node:path");

        const APP_NAME = {json.dumps(app_name)};
        const BUILD_DIR = {json.dumps(build_dir)};
        const SBOM_PATH = {json.dumps(sbom_path)};

        function fail(message) {{
            throw new Error(message);
        }}

        function addPackage(inventory, packagePath, version) {{
            if (typeof version !== "string" || !version.trim()) {{
                fail(`Invalid package version for ${{packagePath}}`);
            }}

            if (
                Object.prototype.hasOwnProperty.call(
                    inventory,
                    packagePath
                )
            ) {{
                fail(
                    `Duplicate package inventory entry: ${{packagePath}}`
                );
            }}

            inventory[packagePath] = version;
        }}

        function collectLegacyDependencies(
            dependencies,
            parentPath,
            inventory
        ) {{
            if (
                !dependencies ||
                typeof dependencies !== "object" ||
                Array.isArray(dependencies)
            ) {{
                return;
            }}

            for (const [name, details] of Object.entries(dependencies)) {{
                if (!details || typeof details !== "object") {{
                    fail(`Invalid lockfile entry for ${{name}}`);
                }}

                const packagePath = parentPath
                    ? `${{parentPath}}/node_modules/${{name}}`
                    : `node_modules/${{name}}`;

                if (details.version) {{
                    addPackage(
                        inventory,
                        packagePath,
                        details.version
                    );
                }}

                collectLegacyDependencies(
                    details.dependencies,
                    packagePath,
                    inventory
                );
            }}
        }}

        const lockPath = path.join(
            BUILD_DIR,
            "package-lock.json"
        );

        const lock = JSON.parse(
            fs.readFileSync(lockPath, "utf8")
        );

        const packages = {{}};

        if (
            lock.packages &&
            typeof lock.packages === "object" &&
            !Array.isArray(lock.packages)
        ) {{
            for (
                const [packagePath, details]
                of Object.entries(lock.packages)
            ) {{
                // The empty path represents the root application.
                if (!packagePath) {{
                    continue;
                }}

                if (!details || typeof details !== "object") {{
                    fail(`Invalid lockfile entry: ${{packagePath}}`);
                }}

                if (details.link === true) {{
                    continue;
                }}

                if (details.version) {{
                    addPackage(
                        packages,
                        packagePath,
                        details.version
                    );
                }}
            }}
        }} else if (
            lock.dependencies &&
            typeof lock.dependencies === "object"
        ) {{
            collectLegacyDependencies(
                lock.dependencies,
                "",
                packages
            );
        }} else {{
            fail(
                "Unsupported or incomplete package-lock.json format"
            );
        }}

        if (Object.keys(packages).length === 0) {{
            fail(
                "Package lockfile produced an empty package inventory"
            );
        }}

        const npmVersion = require("node:child_process")
            .execFileSync(
                "npm",
                ["--version"],
                {{ encoding: "utf8" }}
            )
            .trim();

        const sbom = {{
            app_section: {{
                app_name: APP_NAME,
                description:
                    "Application npm dependency inventory from package-lock.json",
                runtime: "node",
                packages: Object.fromEntries(
                    Object.entries(packages).sort(([a], [b]) =>
                        a.localeCompare(b)
                    )
                )
            }},
            kubapp_data: {{
                description:
                    "KUBAPP dependency audit tool metadata",
                section: {{
                    tools: {{
                        "npm-audit": npmVersion
                    }},
                    packages: {{}}
                }}
            }}
        }};

        fs.writeFileSync(
            SBOM_PATH,
            JSON.stringify(sbom, null, 2) + "\\n",
            {{ encoding: "utf8", flag: "wx" }}
        );

        console.log(`Generated SBOM: ${{SBOM_PATH}}`);
        """
    )

    commands = [
        "set -eu",
        f"rm -rf {shlex.quote(build_dir)}",
        f"mkdir -p {shlex.quote(build_dir)}",
        (
            f"cp -a {shlex.quote(_CONTAINER_COMPONENT)}/. "
            f"{shlex.quote(build_dir)}/"
        ),
        (
            f"cd {shlex.quote(build_dir)} "
            "&& npm ci --no-fund --no-audit"
        ),
        (
            "printf '%s\\n' "
            "'[node_mgt] Running npm dependency vulnerability audit'"
        ),
        (
            f"cd {shlex.quote(build_dir)} "
            "&& npm audit --audit-level=low"
        ),
        (
            f"test -d "
            f"{shlex.quote(build_dir + '/node_modules')}"
        ),
        (
            f"cp -a {shlex.quote(build_dir + '/node_modules')} "
            f"{shlex.quote(dependency_dir + '/node_modules')}"
        ),
        f"node -e {shlex.quote(sbom_script)}",
    ]

    return " && ".join(commands)


def stage_node_dependency(
    *,
    app_name: str,
    component_dir: str | Path,
    manifest: str | Path,
    lockfile: str | Path,
    execution_image: str,
    staging_root: str | Path | None = None,
) -> Path:
    """Install, audit, and stage npm dependencies inside Podman.

    The component is mounted read-only into the preparation container.
    Installation occurs in a temporary copy of the component. The
    resulting dependency directory is stored separately for subsequent
    read-only mounts during component execution.
    """

    if not isinstance(app_name, str) or not app_name.strip():
        raise NodeStagingError(
            "app_name must be a nonempty string."
        )

    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", app_name):
        raise NodeStagingError(
            f"Invalid application name: {app_name!r}"
        )

    if not isinstance(execution_image, str) or not execution_image.strip():
        raise NodeStagingError(
            "execution_image must be a nonempty string."
        )

    config = _get_node_dependency_config()

    try:
        component_path = Path(component_dir).resolve(strict=True)
        manifest_path = Path(manifest).resolve(strict=True)
        lockfile_path = Path(lockfile).resolve(strict=True)

    except (OSError, RuntimeError, TypeError, ValueError) as exc:
        raise NodeStagingError(
            f"Cannot resolve component, manifest, or lockfile: {exc}"
        ) from exc

    if not component_path.is_dir():
        raise NodeStagingError(
            f"Component directory is not a directory: {component_path}"
        )

    if (
        not manifest_path.is_file()
        or manifest_path.name != "package.json"
    ):
        raise NodeStagingError(
            "Node.js dependency staging requires package.json."
        )

    if (
        not lockfile_path.is_file()
        or lockfile_path.name != "package-lock.json"
    ):
        raise NodeStagingError(
            "Node.js dependency staging requires package-lock.json."
        )

    for path, description in (
        (manifest_path, "package.json"),
        (lockfile_path, "package-lock.json"),
    ):
        try:
            path.relative_to(component_path)

        except ValueError as exc:
            raise NodeStagingError(
                f"{description} must be inside the component directory."
            ) from exc

    try:
        package_data = json.loads(
            manifest_path.read_text(encoding="utf-8")
        )

        lock_data = json.loads(
            lockfile_path.read_text(encoding="utf-8")
        )

    except (OSError, json.JSONDecodeError) as exc:
        raise NodeStagingError(
            f"Cannot read npm manifest or lockfile: {exc}"
        ) from exc

    if not isinstance(package_data, dict):
        raise NodeStagingError(
            "package.json must contain a JSON object."
        )

    if not isinstance(lock_data, dict):
        raise NodeStagingError(
            "package-lock.json must contain a JSON object."
        )

    package_name = package_data.get("name")

    if not isinstance(package_name, str) or not package_name.strip():
        raise NodeStagingError(
            "package.json must declare a nonempty package name."
        )

    lock_name = lock_data.get("name")

    if lock_name is not None and lock_name != package_name:
        raise NodeStagingError(
            "package.json and package-lock.json have different package names."
        )

    lockfile_version = lock_data.get("lockfileVersion")

    if (
        not isinstance(lockfile_version, int)
        or isinstance(lockfile_version, bool)
    ):
        raise NodeStagingError(
            "package-lock.json must declare a valid lockfileVersion."
        )

    if staging_root is None:
        root = Path(tempfile.gettempdir()) / "kubapp-ci-dependencies"

    else:
        root = Path(staging_root).resolve()

    try:
        root.mkdir(parents=True, exist_ok=True)

        staging_dir = Path(
            tempfile.mkdtemp(
                prefix="node-",
                dir=str(root),
            )
        ).resolve()

    except OSError as exc:
        raise NodeStagingError(
            f"Cannot create Node.js staging directory: {exc}"
        ) from exc

    try:
        podman = _podman_path()

        _ensure_image_available(
            podman,
            execution_image,
        )

        install_script = _build_install_script(app_name)

        command = [
            podman,
            "run",
            "--rm",
            "--pull=never",
            "--read-only",
            "--security-opt",
            "no-new-privileges",
            "--cpus",
            "1",
            "--memory",
            "1g",
            "--memory-swap",
            "1g",
            "--pids-limit",
            "128",
            "--tmpfs",
            "/tmp:rw,nosuid,nodev,size=256m",
            "--workdir",
            _CONTAINER_COMPONENT,
            "--env",
            "HOME=/tmp",
            "--env",
            "npm_config_cache=/tmp/npm-cache",
            "--env",
            "npm_config_update_notifier=false",
            "--volume",
            f"{component_path}:{_CONTAINER_COMPONENT}:ro",
            "--volume",
            f"{staging_dir}:{_CONTAINER_DEPENDENCIES}:rw",
            execution_image,
            "/bin/sh",
            "-c",
            install_script,
        ]

        _run_podman(
            command,
            label=(
                "Preparing and auditing npm dependencies for "
                f"{component_path.name}"
            ),
        )

        sbom_path = staging_dir / "sbom.json"

        if not sbom_path.is_file():
            raise NodeStagingError(
                "Node.js dependency preparation did not produce an SBOM: "
                f"{sbom_path}"
            )

        dependency_dir = staging_dir / config["dependency_path"]
        executable_dir = staging_dir / config["executable_path"]
        required_path = staging_dir / config["required_path"]

        if not dependency_dir.is_dir():
            raise NodeStagingError(
                "Staged Node.js dependency directory is missing: "
                f"{dependency_dir}"
            )

        if not executable_dir.is_dir():
            raise NodeStagingError(
                "Staged Node.js executable directory is missing: "
                f"{executable_dir}"
            )

        if not required_path.is_file():
            raise NodeStagingError(
                "Staged Node.js dependency environment is missing its "
                f"configured required file: {required_path}"
            )

        metadata = [
            f"execution_image={execution_image}",
            f"manifest={manifest_path}",
            f"lockfile={lockfile_path}",
            f"dependency_directory={dependency_dir}",
            "package_manager=npm",
            "dependency_audit=passed",
            "installation_location=prepared_container",
        ]

        try:
            (staging_dir / ".kubapp-staging-info").write_text(
                "\n".join(metadata) + "\n",
                encoding="utf-8",
            )

        except OSError as exc:
            raise NodeStagingError(
                f"Failed to write staging metadata: {exc}"
            ) from exc

        _publish_sbom(
            sbom_path,
            app_name,
        )

        print(
            "[node_mgt] Prepared and audited npm dependencies at "
            f"{staging_dir}"
        )

        return staging_dir

    except Exception:
        shutil.rmtree(staging_dir, ignore_errors=True)
        raise
