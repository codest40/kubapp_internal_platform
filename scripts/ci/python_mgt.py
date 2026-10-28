"""Prepare isolated Python dependencies for KUBAPP CI."""

from __future__ import annotations
import json
import os
import re
import tempfile
import shlex
import shutil
import subprocess
from pathlib import Path
import textwrap

class PythonStagingError(RuntimeError):
    """Raised when Python dependency preparation fails."""


_CONTAINER_COMPONENT = "/workspace"
_CONTAINER_DEPENDENCIES = "/opt/kubapp-dependencies"
_VENV_NAME = "venv"

# KUBAPP-owned dependency vulnerability scanner.
_PIP_AUDIT_VERSION = "2.10.1"
_PIP_AUDIT_VENV = "/tmp/kubapp-pip-audit-venv"


def _podman_path() -> str:
    """Resolve Podman from supported absolute paths."""

    for candidate in ("/usr/local/bin/podman", "/usr/bin/podman"):
        path = Path(candidate)
        if path.is_file() and path.stat().st_mode & 0o111:
            return str(path)

    raise PythonStagingError(
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
        raise PythonStagingError(
            f"{label}: could not execute Podman: {exc}"
        ) from exc

    if result.returncode != 0:
        #details = (result.stderr or result.stdout or "").strip()
        details = "\n".join(
             part for part in (result.stdout, result.stderr) if part
        ).strip()
        raise PythonStagingError(
            f"{label} failed with exit code {result.returncode}."
            + (f"\n{details}" if details else "")
        )

    if result.stdout:
        print(result.stdout, end="")

    if result.stderr:
        print(result.stderr, end="")

    return result


def _ensure_image_available(podman: str, image: str) -> None:
    """Ensure preparation and execution can use the configured image."""

    result = subprocess.run(
        [podman, "image", "exists", image],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    if result.returncode == 0:
        return

    _run_podman(
        [podman, "pull", image],
        label=f"Pulling Python execution image {image}",
    )

def _publish_sbom(sbom_path: Path, app_name: str) -> Path:
    """Validate and atomically publish an SBOM to the KUBAPP repository."""
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", app_name):
        raise PythonStagingError(
            f"Invalid application name for SBOM publication: {app_name!r}"
        )

    try:
        sbom = json.loads(sbom_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise PythonStagingError(
            f"Cannot read generated SBOM {sbom_path}: {exc}"
        ) from exc

    if not isinstance(sbom, dict):
        raise PythonStagingError("Generated SBOM must be a JSON object")

    app_section = sbom.get("app_section")
    kubapp_section = sbom.get("kubapp_data", {}).get("section") \
        if isinstance(sbom.get("kubapp_data"), dict) else None

    if not isinstance(app_section, dict):
        raise PythonStagingError("SBOM is missing app_section")

    if app_section.get("app_name") != app_name:
        raise PythonStagingError(
            f"SBOM application mismatch: expected {app_name!r}, "
            f"got {app_section.get('app_name')!r}"
        )

    if app_section.get("runtime") != "python":
        raise PythonStagingError("SBOM runtime must be 'python'")

    if not isinstance(app_section.get("packages"), dict):
        raise PythonStagingError("SBOM app_section.packages must be an object")

    if not isinstance(kubapp_section, dict):
        raise PythonStagingError("SBOM is missing kubapp_data.section")

    if not isinstance(kubapp_section.get("tools"), dict):
        raise PythonStagingError("SBOM kubapp_data.section.tools must be an object")

    if not kubapp_section["tools"].get("pip-audit"):
        raise PythonStagingError("SBOM is missing the pip-audit version")

    if not isinstance(kubapp_section.get("packages"), dict):
        raise PythonStagingError(
            "SBOM kubapp_data.section.packages must be an object"
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
        raise PythonStagingError(
            f"Failed to publish SBOM for {app_name}: {exc}"
        ) from exc

    print(f"[python_mgt] Published SBOM: {target}")
    return target

def _build_install_script(
    app_name: str,
    manifest_name: str,
    manifest_relative: Path,
) -> str:
    """Build the dependency installation and verification script."""

    venv_python = (
        f"{_CONTAINER_DEPENDENCIES}/{_VENV_NAME}/bin/python"
    )
    audit_python = f"{_PIP_AUDIT_VENV}/bin/python"
    audit_command = f"{_PIP_AUDIT_VENV}/bin/pip-audit"

    commands = [
        "set -eu",
        (
            f"python -m venv "
            f"{shlex.quote(f'{_CONTAINER_DEPENDENCIES}/{_VENV_NAME}')}"
        ),
        (
            f"{shlex.quote(venv_python)} "
            "-m pip install --upgrade pip"
        ),
    ]

    if manifest_name == "requirements.txt":
        manifest_in_container = (
            Path(_CONTAINER_COMPONENT) / manifest_relative
        )
        commands.append(
            f"{shlex.quote(venv_python)} -m pip install "
            f"-r {shlex.quote(str(manifest_in_container))}"
        )

    elif manifest_name == "pyproject.toml":
        build_dir = "/tmp/kubapp-build"

        commands.extend(
            [
                f"mkdir -p {shlex.quote(build_dir)}",
                (
                    f"cp -a {_CONTAINER_COMPONENT}/. "
                    f"{shlex.quote(build_dir)}/"
                ),
                (
                    f"{shlex.quote(venv_python)} -m pip install "
                    f"{shlex.quote(build_dir)}"
                ),
            ]
        )

    else:
        raise PythonStagingError(
            f"Unsupported Python manifest: {manifest_name}"
        )

    # Install KUBAPP's pinned scanner in a separate environment.
    commands.extend(
        [
            (
                f"python -m venv "
                f"{shlex.quote(_PIP_AUDIT_VENV)}"
            ),
            (
                f"{shlex.quote(audit_python)} -m pip install "
                "--disable-pip-version-check --no-cache-dir "
                f"pip-audit=={shlex.quote(_PIP_AUDIT_VERSION)}"
            ),
            (
                "printf '%s\\n' "
                "'[python_mgt] Inspecting staged Python environment'"
                f" && {shlex.quote(venv_python)} -c "
                + shlex.quote(
                    "import sys, sysconfig, importlib.metadata as m; "
                    "print('Python executable:', sys.executable); "
                    "print('Python version:', sys.version); "
                    "print('Package directory:', sysconfig.get_paths()['purelib']); "
                    "print('Installed distributions:'); "
                    "print('\\n'.join(sorted("
                    "f'{d.metadata.get(\"Name\", \"unknown\")}=={d.version}' "
                    "for d in m.distributions()"
                    "))); "
                    "print('Flask version:', "
                    "m.version('Flask') if "
                    "'Flask' in {d.metadata['Name'] "
                    "for d in m.distributions()} "
                    "else 'not installed')"
                )
            ),
            (
                "printf '%s\\n' "
                "'[python_mgt] Running KUBAPP dependency vulnerability audit'"
                " && "
                f"{shlex.quote(audit_command)} --path \"$("
                f"{shlex.quote(venv_python)} -c "
                + shlex.quote(
                    "import sysconfig; "
                    "print(sysconfig.get_paths()['purelib'])"
                )
                + ")\""
            ),
        ]
    )
    # These checks run only if dependency auditing succeeds.
    commands.append(
        f"{shlex.quote(venv_python)} -m pip check"
    )
    # Generate the SBOM only after the vulnerability audit has passed.
    sbom_path = f"{_CONTAINER_DEPENDENCIES}/sbom.json"
    sbom_script = textwrap.dedent(
        f"""
        import importlib.metadata as metadata
        import json
        import re
        import subprocess
        import sysconfig
        from pathlib import Path

        APP_NAME = {app_name!r}
        SCANNER_PYTHON = {audit_python!r}
        SBOM_PATH = Path({sbom_path!r})

        def normalize_package_name(name):
            return re.sub(r"[-_.]+", "-", name).lower()

        def get_package_inventory(site_packages):
            packages = {{}}

            for distribution in metadata.distributions(path=[site_packages]):
                name = distribution.metadata.get("Name")

                if not name:
                    raise RuntimeError(
                         f"Installed distribution has no package name: {{distribution}}"
                    )

                normalized_name = normalize_package_name(name)

                if normalized_name in packages:
                    raise RuntimeError(
                        f"Duplicate normalized package name: {{normalized_name}}"
                    )

                packages[normalized_name] = distribution.version

            return dict(sorted(packages.items()))

        # Inventory the application environment.
        app_site_packages = sysconfig.get_paths()["purelib"]
        app_packages = get_package_inventory(app_site_packages)

        # Discover the scanner environment's site-packages independently.
        scanner_site_packages = subprocess.check_output(
            [
                SCANNER_PYTHON,
                "-c",
                'import sysconfig; print(sysconfig.get_paths()["purelib"])',
            ],
            text=True,
        ).strip()

        scanner_packages = get_package_inventory(scanner_site_packages)
        # Record pip-audit explicitly as a KUBAPP scanning tool.
        pip_audit_version = scanner_packages.get("pip-audit")

        if pip_audit_version is None:
            raise RuntimeError(
                "pip-audit is missing from the scanner environment"
            )
        app_desc = "Application-specific runtime dependency inventory"
        kubapp_desc = "KUBAPP dependency vulnerability scanning environment inventory"
        sbom = {{
            "app_section": {{
                "app_name": APP_NAME,
                "description": app_desc,
                "runtime": "python",
                "packages": app_packages,
            }},
            "kubapp_data": {{
                "description": kubapp_desc,
                "section": {{
                    "tools": {{
                        "pip-audit": pip_audit_version,
                    }},
                   "packages": scanner_packages,
                }}
            }},
        }}

        SBOM_PATH.write_text(
            json.dumps(sbom, indent=2, sort_keys=True) + "\\n",
            encoding="utf-8",
        )

        print(f"Generated SBOM: {{SBOM_PATH}}")
        """
    )

    commands.append(
        f"{shlex.quote(venv_python)} -c {shlex.quote(sbom_script)}"
    )

    commands.append(
        f"{shlex.quote(venv_python)} -c "
        f"{shlex.quote(sbom_script)}"
    )
    commands.append(
        f"{shlex.quote(venv_python)} -c "
        "'import sys; print(\"Prepared interpreter:\", sys.executable); "
        "print(\"Python version:\", sys.version)'"
    )

    return " && ".join(commands)


def stage_python_dependency(
    *,
    app_name: str,
    component_dir: str | Path,
    manifest: str | Path,
    execution_image: str,
    staging_root: str | Path | None = None,
) -> Path:
    """Prepare and audit Python dependencies inside a Podman container.

    The GitHub runner coordinates Podman but does not install the project's
    Python dependencies into its own interpreter. Installation and the
    KUBAPP-owned dependency vulnerability audit happen inside the configured
    execution image. The resulting directory is retained for subsequent
    read-only mounts into CI execution containers.
    """
    if not isinstance(app_name, str) or not app_name.strip():
        raise PythonStagingError(
            "app_name must be a nonempty string."
        )
    try:
        component_path = Path(component_dir).resolve(strict=True)
        manifest_path = Path(manifest).resolve(strict=True)
    except (OSError, RuntimeError) as exc:
        raise PythonStagingError(
            f"Cannot resolve component or manifest: {exc}"
        ) from exc

    if not component_path.is_dir():
        raise PythonStagingError(
            f"Component directory is not a directory: {component_path}"
        )

    if not manifest_path.is_file():
        raise PythonStagingError(
            f"Dependency manifest is not a file: {manifest_path}"
        )

    if manifest_path.name not in {"requirements.txt", "pyproject.toml"}:
        raise PythonStagingError(
            f"Unsupported Python manifest: {manifest_path.name}"
        )

    try:
        manifest_relative = manifest_path.relative_to(component_path)
    except ValueError as exc:
        raise PythonStagingError(
            "The Python manifest must be inside the component directory."
        ) from exc

    if not isinstance(execution_image, str) or not execution_image.strip():
        raise PythonStagingError(
            "execution_image must be a nonempty string."
        )

    if staging_root is None:
        root = Path(tempfile.gettempdir()) / "kubapp-ci-dependencies"
    else:
        root = Path(staging_root).resolve()

    root.mkdir(parents=True, exist_ok=True)
    staging_dir = Path(
        tempfile.mkdtemp(prefix="python-", dir=str(root))
    ).resolve()

    try:
        podman = _podman_path()
        _ensure_image_available(podman, execution_image)

        install_script = _build_install_script(
            app_name,
            manifest_path.name,
            manifest_relative,
        )
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
            "PIP_NO_CACHE_DIR=1",
            "--env",
            "PIP_DISABLE_PIP_VERSION_CHECK=1",
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
                "Preparing and auditing Python dependencies for "
                f"{component_path.name}"
            ),
        )

        sbom_path = staging_dir / "sbom.json"
        if not sbom_path.is_file():
            raise PythonStagingError(
                "Python dependency preparation did not produce an SBOM: "
                f"{sbom_path}"
            )

        _publish_sbom(sbom_path, app_name)

        venv_python = (
            staging_dir / _VENV_NAME / "bin" / "python"
        )

        if not (venv_python.is_file() or venv_python.is_symlink()):
            raise PythonStagingError(
                "Preparation finished without producing the virtual "
                f"environment interpreter: {venv_python}"
            )

        metadata = [
            f"execution_image={execution_image}",
            f"manifest={manifest_path}",
            f"virtual_environment={staging_dir / _VENV_NAME}",
            f"pip_audit_version={_PIP_AUDIT_VERSION}",
            "dependency_audit=passed",
            "installation_location=prepared_container",
        ]

        (staging_dir / ".kubapp-staging-info").write_text(
            "\n".join(metadata) + "\n",
            encoding="utf-8",
        )

        print(
            "[python_mgt] Prepared and audited Python environment at "
            f"{staging_dir}"
        )
        return staging_dir

    except Exception:
        shutil.rmtree(staging_dir, ignore_errors=True)
        raise
