"""Execution boundary for developer-controlled KUBAPP CI commands.

Component commands execute through Podman with configured resource limits,
filesystem restrictions, and network policy. Failure to establish the
container execution boundary must not trigger host-subprocess execution.
"""

from __future__ import annotations

import os
import re
import subprocess
import time
import warnings
from dataclasses import dataclass
from pathlib import Path
from typing import Mapping, Sequence

from podman_execution import PodmanExecution, PodmanExecutionError
from variables import RUNTIME_DEPENDENCY_CONFIG


_ENV_NAME_PATTERN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
_ENV_VALUE_LIMIT = 32_768
_ERROR_OUTPUT_LIMIT = 4_000


class ComponentEnvironmentError(RuntimeError):
    """Raised when a component command cannot be executed correctly."""

    def __init__(
        self,
        message: str,
        *,
        returncode: int | None = None,
        stdout: str = "",
        stderr: str = "",
    ) -> None:
        super().__init__(message)
        self.returncode = returncode
        self.stdout = stdout
        self.stderr = stderr


@dataclass(frozen=True)
class ExecutionPolicy:
    network: str = "disabled"
    filesystem: str = "restricted"
    no_new_privileges: bool = True
    hide_docker_socket: bool = True
    cpu_quota_percent: int = 100
    memory_bytes: int = 512 * 1024 * 1024
    process_limit: int = 64
    timeout_seconds: int = 120

    def validate(self) -> None:
        if self.network not in {"disabled", "enabled"}:
            raise ComponentEnvironmentError(
                f"Unsupported network policy: {self.network!r}"
            )

        if self.filesystem != "restricted":
            raise ComponentEnvironmentError(
                f"Unsupported filesystem policy: {self.filesystem!r}"
            )

        for name in (
            "cpu_quota_percent",
            "memory_bytes",
            "process_limit",
            "timeout_seconds",
        ):
            value = getattr(self, name)
            if (
                not isinstance(value, int)
                or isinstance(value, bool)
                or value <= 0
            ):
                raise ComponentEnvironmentError(
                    f"Execution policy {name} must be a positive integer."
                )


class ComponentEnvironment:
    def __init__(
        self,
        app_name: str,
        component_dir: str | Path,
        component_env: Mapping[str, str],
        writable_paths: Sequence[str | Path] | None = None,
        policy: ExecutionPolicy | None = None,
        execution_image: str | None = None,
        dependency_dir: str | Path | None = None,
        runtime: str | None = None,
    ) -> None:
        if not isinstance(app_name, str) or not app_name.strip():
            raise ComponentEnvironmentError(
                "app_name must be a nonempty string."
            )

        if not isinstance(component_env, Mapping):
            raise ComponentEnvironmentError(
                "component_env must be an explicitly prepared mapping."
            )

        if runtime not in RUNTIME_DEPENDENCY_CONFIG:
            raise ComponentEnvironmentError(
                f"Unsupported dependency runtime: {runtime!r}"
            )

        if (
            not isinstance(execution_image, str)
            or not execution_image.strip()
        ):
            raise ComponentEnvironmentError(
                "A nonempty execution_image is required."
            )

        self.runtime = runtime
        self.runtime_dependency_config = RUNTIME_DEPENDENCY_CONFIG[runtime]
        self.execution_image = execution_image

        self.app_name = app_name
        self.component_dir = Path(component_dir).resolve()
        self.policy = policy or ExecutionPolicy()
        self.policy.validate()
        self.dependency_dir: Path | None = None

        if not self.component_dir.is_dir():
            raise ComponentEnvironmentError(
                f"[{app_name}] Component directory does not exist."
            )

        self.component_env = self._validate_environment(component_env)

        supplied_paths = (
            [self.component_dir]
            if writable_paths is None
            else writable_paths
        )
        self.writable_paths = self._validate_writable_paths(supplied_paths)
        self.last_execution_mode: str | None = None

        if dependency_dir is not None:
            self.set_dependency_environment(dependency_dir)

    @staticmethod
    def _validate_environment(
        component_env: Mapping[str, str],
    ) -> dict[str, str]:
        validated: dict[str, str] = {}

        for name, value in component_env.items():
            if (
                not isinstance(name, str)
                or not _ENV_NAME_PATTERN.fullmatch(name)
            ):
                raise ComponentEnvironmentError(
                    "Component environment contains an invalid variable name."
                )

            if not isinstance(value, str):
                raise ComponentEnvironmentError(
                    f"Environment variable {name!r} must have a string value."
                )

            if "\x00" in value:
                raise ComponentEnvironmentError(
                    f"Environment variable {name!r} contains a NUL byte."
                )

            if len(value) > _ENV_VALUE_LIMIT:
                raise ComponentEnvironmentError(
                    f"Environment variable {name!r} exceeds the size limit."
                )

            validated[name] = value

        return validated

    def _validate_writable_paths(
        self,
        paths: Sequence[str | Path],
    ) -> list[Path]:
        validated: list[Path] = []

        for supplied_path in paths:
            try:
                path = Path(supplied_path).resolve(strict=True)
            except (OSError, RuntimeError) as exc:
                raise ComponentEnvironmentError(
                    f"Cannot resolve writable path: {supplied_path}"
                ) from exc

            if not path.is_dir():
                raise ComponentEnvironmentError(
                    f"Writable path must be an existing directory: {path}"
                )

            if path == Path("/"):
                raise ComponentEnvironmentError(
                    "The filesystem root cannot be writable."
                )

            validated.append(path)

        if self.component_dir not in validated:
            raise ComponentEnvironmentError(
                "The component directory must be explicitly writable."
            )

        return list(dict.fromkeys(validated))

    @staticmethod
    def _launcher_environment() -> dict[str, str]:
        env = {
            "HOME": str(Path.home()),
            "PATH": "/usr/local/bin:/usr/bin:/bin",
            "LANG": "C.UTF-8",
        }

        for name in ("XDG_RUNTIME_DIR", "DBUS_SESSION_BUS_ADDRESS"):
            value = os.environ.get(name)
            if value:
                env[name] = value

        return env

    def _validate_command(self, command: Sequence[str]) -> list[str]:
        if isinstance(command, (str, bytes)):
            raise ComponentEnvironmentError(
                "Command must be a sequence of arguments, not a string."
            )

        if not command:
            raise ComponentEnvironmentError("Command cannot be empty.")

        if any(
            not isinstance(part, str) or not part or "\x00" in part
            for part in command
        ):
            raise ComponentEnvironmentError(
                "Command arguments must be nonempty strings without NUL bytes."
            )

        return list(command)

    def _resolve_working_directory(
        self,
        cwd: str | Path | None,
    ) -> Path:
        try:
            working_dir = Path(
                cwd if cwd is not None else self.component_dir
            ).resolve(strict=True)
        except (OSError, RuntimeError) as exc:
            raise ComponentEnvironmentError(
                "Cannot resolve the command working directory."
            ) from exc

        if not working_dir.is_dir():
            raise ComponentEnvironmentError(
                f"Command working directory is not a directory: {working_dir}"
            )

        try:
            working_dir.relative_to(self.component_dir)
        except ValueError as exc:
            raise ComponentEnvironmentError(
                "Command working directory must remain inside the component."
            ) from exc

        return working_dir

    def _resolve_timeout(self, timeout_seconds: int | None) -> int:
        timeout = (
            self.policy.timeout_seconds
            if timeout_seconds is None
            else timeout_seconds
        )

        if (
            not isinstance(timeout, int)
            or isinstance(timeout, bool)
            or timeout <= 0
        ):
            raise ComponentEnvironmentError(
                "timeout_seconds must be a positive integer."
            )

        return timeout

    def _report_degraded_execution(self, reason: str) -> None:
        message = (
            f"[{self.app_name}] WARNING: {reason} "
            "OS-level isolation must not be assumed where the relevant "
            "restriction has not been demonstrated."
        )
        warnings.warn(message, RuntimeWarning, stacklevel=2)
        print(message, flush=True)

    @staticmethod
    def _limited_output(value: str) -> str:
        if len(value) <= _ERROR_OUTPUT_LIMIT:
            return value

        return value[:_ERROR_OUTPUT_LIMIT] + "\n[output truncated]"

    def set_dependency_environment(
        self,
        dependency_dir: str | Path,
    ) -> None:
        """Attach a prepared dependency directory for read-only execution."""

        try:
            path = Path(dependency_dir).resolve(strict=True)
        except (OSError, RuntimeError) as exc:
            raise ComponentEnvironmentError(
                "Dependency environment must be an accessible directory."
            ) from exc

        if not path.is_dir():
            raise ComponentEnvironmentError(
                "Dependency environment must be an existing directory."
            )

        config = self.runtime_dependency_config
        if not isinstance(config, dict):
            raise ComponentEnvironmentError(
                f"Incomplete dependency configuration for runtime: "
                f"{self.runtime!r}"
            )

        runtime_dir = path / config["dependency_path"]
        if not runtime_dir.is_dir():
            raise ComponentEnvironmentError(
                "Prepared dependency environment is missing its runtime "
                f"directory: {config['dependency_path']}"
            )

        required_path = path / config["required_path"]
        if not (
            required_path.is_file()
            or required_path.is_symlink()
        ):
            raise ComponentEnvironmentError(
                "Prepared dependency environment is missing its required "
                f"runtime file: {config['required_path']}"
            )

        self.dependency_dir = path

    def run(
        self,
        command: Sequence[str],
        cwd: str | Path | None = None,
        label: str | None = None,
        timeout_seconds: int | None = None,
    ) -> subprocess.CompletedProcess[str]:
        command_args = self._validate_command(command)
        working_dir = self._resolve_working_directory(cwd)
        timeout = self._resolve_timeout(timeout_seconds)
        command_label = label or "Component command"
        start_time = time.monotonic()

        if not isinstance(self.execution_image, str) or not self.execution_image:
            raise ComponentEnvironmentError(
                f"[{self.app_name}] No execution image has been configured."
            )

        if self.policy.network == "disabled":
            self._report_degraded_execution(
                "Disabled network policy is implemented by this backend."
            )

        try:
            backend = PodmanExecution(
                image=self.execution_image,
                component_dir=self.component_dir,
                component_env=self.component_env,
                writable_paths=self.writable_paths,
                cpu_quota_percent=self.policy.cpu_quota_percent,
                memory_bytes=self.policy.memory_bytes,
                process_limit=self.policy.process_limit,
                no_new_privileges=self.policy.no_new_privileges,
                hide_docker_socket=self.policy.hide_docker_socket,
                network=self.policy.network,
                dependency_dir=self.dependency_dir,
                runtime=self.runtime,
            )

            result = backend.run(
                command=command_args,
                cwd=working_dir,
                timeout_seconds=timeout,
            )
            self.last_execution_mode = "podman"

        except PodmanExecutionError as exc:
            self.last_execution_mode = "podman_failed"
            raise ComponentEnvironmentError(
                f"[{self.app_name}] Unable to execute {command_label} "
                f"through Podman: {exc}"
            ) from exc

        elapsed = time.monotonic() - start_time

        if result.returncode != 0:
            stdout = result.stdout or ""
            stderr = result.stderr or ""

            summary = (
                f"[{self.app_name}] {command_label} failed with exit code "
                f"{result.returncode} after {elapsed:.2f}s."
            )

            if stdout:
                summary += "\nstdout:\n" + self._limited_output(stdout)

            if stderr:
                summary += "\nstderr:\n" + self._limited_output(stderr)

            raise ComponentEnvironmentError(
                summary,
                returncode=result.returncode,
                stdout=stdout,
                stderr=stderr,
            )

        return result
