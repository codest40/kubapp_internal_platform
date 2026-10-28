"""Podman execution backend for developer-controlled KUBAPP CI commands."""

from __future__ import annotations

import os
import subprocess
import time
import uuid
from pathlib import Path
from typing import Mapping, Sequence

from variables import RUNTIME_DEPENDENCY_CONFIG


class PodmanExecutionError(RuntimeError):
    """Raised when the Podman execution boundary cannot be established."""


class PodmanExecution:
    """Execute one command in a disposable Podman container."""

    CONTAINER_WORKDIR = "/workspace"
    CONTAINER_HOME = "/tmp/kubapp-home"
    CONTAINER_DEPENDENCY_DIR = "/opt/kubapp-dependencies"

    def __init__(
        self,
        *,
        image: str,
        component_dir: Path,
        component_env: Mapping[str, str],
        writable_paths: Sequence[Path],
        cpu_quota_percent: int,
        memory_bytes: int,
        process_limit: int,
        no_new_privileges: bool,
        hide_docker_socket: bool,
        network: str,
        dependency_dir: Path | None = None,
        runtime: str | None = None,
    ) -> None:
        if not isinstance(image, str) or not image.strip():
            raise PodmanExecutionError(
                "A nonempty execution image is required."
            )

        if network not in {"disabled", "enabled"}:
            raise PodmanExecutionError(
                f"Unsupported network policy: {network!r}"
            )

        if runtime not in RUNTIME_DEPENDENCY_CONFIG:
            raise PodmanExecutionError(
                f"Unsupported dependency runtime: {runtime!r}"
            )

        config = RUNTIME_DEPENDENCY_CONFIG[runtime]
        if not isinstance(config, dict) or not all(
            key in config
            for key in (
                "dependency_path",
                "executable_path",
                "required_path",
            )
        ):
            raise PodmanExecutionError(
                f"Incomplete dependency configuration for runtime: {runtime!r}"
            )

        self.runtime = runtime
        self.runtime_dependency_config = config

        self.image = image
        self.component_dir = Path(component_dir).resolve(strict=True)
        self.component_env = dict(component_env)
        self.writable_paths = [
            Path(path).resolve(strict=True) for path in writable_paths
        ]
        self.cpu_quota_percent = cpu_quota_percent
        self.memory_bytes = memory_bytes
        self.process_limit = process_limit
        self.no_new_privileges = no_new_privileges
        self.hide_docker_socket = hide_docker_socket
        self.network = network
        self.dependency_dir: Path | None = None

        if dependency_dir is not None:
            dependency_path = Path(dependency_dir).resolve(strict=True)

            if not dependency_path.is_dir():
                raise PodmanExecutionError(
                    "Dependency environment must be a directory."
                )

            runtime_dir = dependency_path / config["dependency_path"]
            if not runtime_dir.is_dir():
                raise PodmanExecutionError(
                    "Dependency environment is missing its runtime directory: "
                    f"{config['dependency_path']}"
                )

            required_path = dependency_path / config["required_path"]
            if not (
                required_path.is_file()
                or required_path.is_symlink()
            ):
                raise PodmanExecutionError(
                    "Dependency environment is missing its required "
                    f"runtime file: {config['required_path']}"
                )

            self.dependency_dir = dependency_path

    @staticmethod
    def _podman_path() -> str:
        """Resolve Podman from a controlled PATH."""

        for path in ("/usr/local/bin/podman", "/usr/bin/podman"):
            if os.path.isfile(path) and os.access(path, os.X_OK):
                return path

        raise PodmanExecutionError(
            "Podman executable was not found in the supported paths."
        )

    def _build_command(
        self,
        command: Sequence[str],
        cwd: Path,
        container_name: str,
    ) -> list[str]:
        podman = self._podman_path()

        args = [
            podman,
            "run",
            "--name",
            container_name,
            "--attach=stdout",
            "--attach=stderr",
            "--interactive",
            "--rm",
            "--pull=never",
            "--read-only",
            "--tmpfs",
            "/tmp:rw,nosuid,nodev,size=128m",
            "--tmpfs",
            f"{self.CONTAINER_HOME}:rw,nosuid,nodev,size=16m",
            "--workdir",
            str(
                Path(self.CONTAINER_WORKDIR)
                / cwd.relative_to(self.component_dir)
            ),
            "--cpus",
            str(self.cpu_quota_percent / 100),
            "--memory",
            str(self.memory_bytes),
            "--memory-swap",
            str(self.memory_bytes),
            "--pids-limit",
            str(self.process_limit),
            "--user",
            "0:0",
            "--env",
            f"HOME={self.CONTAINER_HOME}",
            "--env",
            self._container_path_value(),
            "--env",
            "LANG=C.UTF-8",
            "--mount",
            (
                f"type=bind,src={self.component_dir},"
                f"dst={self.CONTAINER_WORKDIR},rw"
            ),
        ]

        if self.no_new_privileges:
            args.extend(
                ["--security-opt", "no-new-privileges"]
            )

        if self.network == "disabled":
            args.extend(["--network", "none"])

        if self.hide_docker_socket:
            # The container receives no host socket mount.
            pass

        for path in self.writable_paths:
            if path == self.component_dir:
                continue

            try:
                relative = path.relative_to(self.component_dir)
            except ValueError as exc:
                raise PodmanExecutionError(
                    "Writable paths outside the component directory "
                    "are not supported by the Podman backend."
                ) from exc

            target = str(Path(self.CONTAINER_WORKDIR) / relative)
            args.extend(
                [
                    "--mount",
                    f"type=bind,src={path},dst={target},rw",
                ]
            )

        if self.dependency_dir is not None:
            args.extend(
                [
                    "--mount",
                    (
                        f"type=bind,src={self.dependency_dir},"
                        f"dst={self.CONTAINER_DEPENDENCY_DIR},ro"
                    ),
                ]
            )

            if self.runtime == "node":
                node_modules = (
                    self.dependency_dir
                    / self.runtime_dependency_config["dependency_path"]
                )
                args.extend(
                    [
                        "--mount",
                        (
                            f"type=bind,src={node_modules},"
                            f"dst={self.CONTAINER_WORKDIR}/node_modules,ro"
                        ),
                    ]
                )

        reserved_variables = {
            "HOME",
            "PATH",
            "LANG",
        }
        for name in sorted(self.component_env):
            if name in reserved_variables:
                continue
            args.extend(["--env", name])

        args.append(self.image)
        args.extend(command)
        return args

    def _container_path_value(self) -> str:
        if (
            self.dependency_dir is not None
            and self.runtime_dependency_config is not None
        ):
            executable_path = (
                f"{self.CONTAINER_DEPENDENCY_DIR}/"
                f"{self.runtime_dependency_config['executable_path']}"
            )
            return f"PATH={executable_path}:/usr/local/bin:/usr/bin:/bin"

        return "PATH=/usr/local/bin:/usr/bin:/bin"

    @staticmethod
    def _terminate_container(
        podman: str,
        container_name: str,
    ) -> None:
        """Attempt bounded container termination and removal."""

        try:
            subprocess.run(
                [podman, "kill", container_name],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=5,
                check=False,
            )
        except (OSError, subprocess.TimeoutExpired):
            pass

        try:
            subprocess.run(
                [podman, "rm", "--force", container_name],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=5,
                check=False,
            )
        except (OSError, subprocess.TimeoutExpired):
            pass

    def run(
        self,
        command: Sequence[str],
        cwd: Path,
        timeout_seconds: int,
    ) -> subprocess.CompletedProcess[str]:
        """Run a single command in a fresh container."""

        podman = self._podman_path()
        container_name = f"kubapp-ci-{uuid.uuid4().hex[:20]}"

        args = self._build_command(
            command=command,
            cwd=cwd,
            container_name=container_name,
        )

        launcher_env = {
            "HOME": str(Path.home()),
            "PATH": "/usr/local/bin:/usr/bin:/bin",
            "LANG": "C.UTF-8",
        }
        launcher_env.update(self.component_env)

        start = time.monotonic()

        try:
            result = subprocess.run(
                args,
                cwd=self.component_dir,
                env=launcher_env,
                stdin=subprocess.DEVNULL,
                text=True,
                capture_output=True,
                check=False,
                timeout=timeout_seconds,
            )

        except subprocess.TimeoutExpired as exc:
            self._terminate_container(podman, container_name)
            raise PodmanExecutionError(
                f"Podman command exceeded its {timeout_seconds}s timeout."
            ) from exc

        except OSError as exc:
            self._terminate_container(podman, container_name)
            raise PodmanExecutionError(
                "Unable to launch the Podman execution boundary."
            ) from exc

        finally:
            self._terminate_container(podman, container_name)

        elapsed = time.monotonic() - start

        if result.returncode != 0:
            return subprocess.CompletedProcess(
                args=list(command),
                returncode=result.returncode,
                stdout=result.stdout,
                stderr=(
                    result.stderr
                    + f"\n[KUBAPP] Podman execution elapsed: {elapsed:.2f}s"
                ),
            )

        return subprocess.CompletedProcess(
            args=list(command),
            returncode=0,
            stdout=result.stdout,
            stderr=result.stderr,
        )
