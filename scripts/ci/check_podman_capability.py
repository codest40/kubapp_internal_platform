"""Assess Podman execution-boundary capabilities for KUBAPP CI.

A WARNING means a control could not be demonstrated.
NOT_ASSESSED means a check could not run or its result could not be verified.
BLOCK is reserved for explicit policy decisions; this diagnostic does not
make execution-policy decisions.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import uuid

from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import Sequence


class SandboxBackendError(RuntimeError):
    """Raised when a Podman capability assessment cannot run correctly."""


class AssessmentStatus(str, Enum):
    PASS = "PASS"
    WARNING = "WARNING"
    BLOCK = "BLOCK"
    NOT_ASSESSED = "NOT_ASSESSED"


@dataclass(frozen=True)
class CapabilityResult:
    """Result of an individual capability assessment."""

    name: str
    status: AssessmentStatus
    detail: str

    @property
    def supported(self) -> bool:
        return self.status == AssessmentStatus.PASS


@dataclass(frozen=True)
class BackendReport:
    """Summary of Podman execution-boundary capabilities."""

    capabilities: tuple[CapabilityResult, ...]

    @property
    def blocked(self) -> bool:
        return any(
            result.status == AssessmentStatus.BLOCK
            for result in self.capabilities
        )

    @property
    def has_warnings(self) -> bool:
        return any(
            result.status == AssessmentStatus.WARNING
            for result in self.capabilities
        )

    @property
    def not_assessed(self) -> tuple[CapabilityResult, ...]:
        return tuple(
            result
            for result in self.capabilities
            if result.status == AssessmentStatus.NOT_ASSESSED
        )

    @property
    def supported(self) -> bool:
        """True only when every reported capability passed."""
        return bool(self.capabilities) and all(
            result.status == AssessmentStatus.PASS
            for result in self.capabilities
        )

    @property
    def unsupported(self) -> tuple[CapabilityResult, ...]:
        return tuple(
            result
            for result in self.capabilities
            if result.status == AssessmentStatus.WARNING
        )

    def summary(self) -> str:
        lines = ["Podman execution-boundary capability report:"]

        for result in self.capabilities:
            lines.append(
                f"[{result.status.value}] "
                f"{result.name}: {result.detail}"
            )

        if self.blocked:
            overall = "BLOCKED BY EXPLICIT POLICY"
        elif self.has_warnings or self.not_assessed:
            overall = "DEGRADED - WARNINGS OR UNASSESSED CONTROLS"
        elif self.supported:
            overall = "ALL ASSESSED CONTROLS PASSED"
        else:
            overall = "NO CAPABILITIES ASSESSED"

        lines.append(f"Overall: {overall}")
        return "\n".join(lines)


class PodmanSandboxBackend:
    """Assess Podman availability and demonstrable container controls."""

    def __init__(
        self,
        *,
        podman: str | None = None,
        probe_image: str | None = None,
        probe_timeout_seconds: int = 10,
        image_pull_timeout_seconds: int = 30,
    ) -> None:
        for name, value in (
            ("probe_timeout_seconds", probe_timeout_seconds),
            ("image_pull_timeout_seconds", image_pull_timeout_seconds),
        ):
            if (
                not isinstance(value, int)
                or isinstance(value, bool)
                or value <= 0
            ):
                raise ValueError(f"{name} must be a positive integer.")

        self.podman = podman or shutil.which("podman")
        self.probe_image = (
            probe_image
            or os.environ.get(
                "KUBAPP_PODMAN_PROBE_IMAGE",
                "docker.io/library/alpine:3.22",
            )
        )
        self.probe_timeout_seconds = probe_timeout_seconds
        self.image_pull_timeout_seconds = image_pull_timeout_seconds
        self._image_ready = False

    @staticmethod
    def _result(
        name: str,
        status: AssessmentStatus,
        detail: str,
    ) -> CapabilityResult:
        return CapabilityResult(
            name=name,
            status=status,
            detail=" ".join(detail.split()),
        )

    def _run(
        self,
        args: Sequence[str],
        *,
        timeout: int | None = None,
    ) -> subprocess.CompletedProcess[str]:
        """Run a trusted Podman diagnostic command."""

        if not self.podman:
            raise SandboxBackendError("Podman is unavailable.")

        try:
            return subprocess.run(
                [self.podman, *args],
                text=True,
                capture_output=True,
                check=False,
                timeout=timeout or self.probe_timeout_seconds,
            )
        except subprocess.TimeoutExpired as exc:
            raise SandboxBackendError(
                "The Podman diagnostic command timed out."
            ) from exc
        except OSError as exc:
            raise SandboxBackendError(
                "Unable to start the Podman diagnostic command."
            ) from exc

    def _run_container_probe(
        self,
        command: Sequence[str],
        *,
        options: Sequence[str] = (),
        timeout: int | None = None,
    ) -> subprocess.CompletedProcess[str]:
        """Run a fixed diagnostic command inside a disposable container."""

        if not self._image_ready:
            raise SandboxBackendError(
                "The Podman diagnostic image is unavailable."
            )

        args = [
            "run",
            "--rm",
            "--pull=never",
            *options,
            self.probe_image,
            *command,
        ]

        return self._run(args, timeout=timeout)

    def _prepare_image(self) -> CapabilityResult:
        """Ensure a probe image is available, with a bounded pull attempt."""

        exists = self._run(
            ["image", "exists", self.probe_image]
        )

        if exists.returncode == 0:
            self._image_ready = True
            return self._result(
                "probe_image",
                AssessmentStatus.PASS,
                f"Diagnostic image is available: {self.probe_image}.",
            )

        pull = self._run(
            ["pull", self.probe_image],
            timeout=self.image_pull_timeout_seconds,
        )

        if pull.returncode == 0:
            self._image_ready = True
            return self._result(
                "probe_image",
                AssessmentStatus.PASS,
                f"Diagnostic image was pulled successfully: "
                f"{self.probe_image}.",
            )

        detail = (
            pull.stderr
            or pull.stdout
            or "Podman could not obtain the diagnostic image."
        )

        return self._result(
            "probe_image",
            AssessmentStatus.NOT_ASSESSED,
            f"Container-level probes are unavailable: {detail[-500:]}",
        )

    def _probe_rootless(self) -> CapabilityResult:
        """Check Podman's reported rootless operating mode."""

        result = self._run(["info", "--format", "json"])

        if result.returncode != 0:
            return self._result(
                "rootless_execution",
                AssessmentStatus.WARNING,
                "Podman info failed; rootless execution could not be verified.",
            )

        try:
            info = json.loads(result.stdout)
            rootless = info["host"]["security"]["rootless"]
        except (ValueError, KeyError, TypeError):
            return self._result(
                "rootless_execution",
                AssessmentStatus.NOT_ASSESSED,
                "Podman's rootless status could not be parsed.",
            )

        if rootless is True:
            return self._result(
                "rootless_execution",
                AssessmentStatus.PASS,
                "Podman reports rootless operation.",
            )

        if rootless is False:
            return self._result(
                "rootless_execution",
                AssessmentStatus.WARNING,
                "Podman reports rootful operation.",
            )

        return self._result(
            "rootless_execution",
            AssessmentStatus.NOT_ASSESSED,
            "Podman did not provide a boolean rootless status.",
        )

    def _probe_user_namespace(self) -> CapabilityResult:
        """Compare host and container user namespace identifiers."""

        try:
            host = Path("/proc/self/ns/user").resolve()
        except OSError:
            return self._result(
                "user_namespace",
                AssessmentStatus.WARNING,
                "The host user namespace identifier could not be read.",
            )

        result = self._run_container_probe(
            ["readlink", "/proc/self/ns/user"]
        )

        if result.returncode != 0:
            return self._result(
                "user_namespace",
                AssessmentStatus.WARNING,
                "The container user namespace could not be inspected.",
            )

        container_ns = result.stdout.strip()

        if not container_ns:
            return self._result(
                "user_namespace",
                AssessmentStatus.NOT_ASSESSED,
                "The container returned no user namespace identifier.",
            )

        host_result = subprocess.run(
            ["/usr/bin/readlink", "/proc/self/ns/user"],
            text=True,
            capture_output=True,
            check=False,
            timeout=self.probe_timeout_seconds,
        )

        if host_result.returncode != 0:
            return self._result(
                "user_namespace",
                AssessmentStatus.WARNING,
                "The host user namespace could not be read.",
            )

        if container_ns != host_result.stdout.strip():
            return self._result(
                "user_namespace",
                AssessmentStatus.PASS,
                "The container uses a different user namespace.",
            )

        return self._result(
            "user_namespace",
            AssessmentStatus.WARNING,
            "A separate user namespace was not demonstrated.",
        )

    def _probe_no_new_privileges(self) -> CapabilityResult:
        result = self._run_container_probe(
            [
                "sh",
                "-c",
                "grep '^NoNewPrivs:' /proc/self/status",
            ],
            options=["--security-opt=no-new-privileges"],
        )

        verified = (
            result.returncode == 0
            and any(
                line.split() == ["NoNewPrivs:", "1"]
                for line in result.stdout.splitlines()
            )
        )

        return self._result(
            "no_new_privileges",
            (
                AssessmentStatus.PASS
                if verified
                else AssessmentStatus.WARNING
            ),
            (
                "The container process reports NoNewPrivs=1."
                if verified
                else "NoNewPrivs=1 was not demonstrated."
            ),
        )

    def _probe_read_only_rootfs(self) -> CapabilityResult:
        """Verify that a read-only root filesystem prevents a write."""

        result = self._run_container_probe(
            [
                "sh",
                "-c",
                "if touch /etc/kubapp-probe-write-test 2>/dev/null; "
                "then exit 1; else exit 0; fi",
            ],
            options=["--read-only"],
        )

        verified = result.returncode == 0

        return self._result(
            "read_only_root_filesystem",
            (
                AssessmentStatus.PASS
                if verified
                else AssessmentStatus.WARNING
            ),
            (
                "A write to /etc was denied with a read-only root filesystem."
                if verified
                else "The expected root-filesystem write restriction "
                "was not demonstrated."
            ),
        )

    def _probe_network_isolation(self) -> CapabilityResult:
        """Verify that --network=none creates a separate network namespace."""

        host_result = subprocess.run(
            ["/usr/bin/readlink", "/proc/self/ns/net"],
            text=True,
            capture_output=True,
            check=False,
            timeout=self.probe_timeout_seconds,
        )

        if host_result.returncode != 0:
            return self._result(
                "network_isolation",
                AssessmentStatus.WARNING,
                "The host network namespace could not be read.",
            )

        result = self._run_container_probe(
            ["/usr/bin/readlink", "/proc/self/ns/net"],
            options=["--network=none"],
        )

        if result.returncode != 0:
            return self._result(
                "network_isolation",
                AssessmentStatus.WARNING,
                "The isolated container network namespace could not be read.",
            )

        host_ns = host_result.stdout.strip()
        container_ns = result.stdout.strip()

        verified = bool(host_ns and container_ns and host_ns != container_ns)

        return self._result(
            "network_isolation",
            (
                AssessmentStatus.PASS
                if verified
                else AssessmentStatus.WARNING
            ),
            (
                "The container has a different network namespace "
                "under --network=none."
                if verified
                else "A separate network namespace was not demonstrated."
            ),
        )

    def _probe_cpu_limit(self) -> CapabilityResult:
        """Verify the CPU quota configured by --cpus=0.5."""

        result = self._run_container_probe(
            [
                "sh",
                "-c",
                "cat /sys/fs/cgroup/cpu.max",
            ],
            options=["--cpus=0.5"],
        )

        if result.returncode != 0:
            return self._result(
                "cpu_limit",
                AssessmentStatus.WARNING,
                "The container CPU quota could not be inspected.",
            )

        try:
            quota, period = result.stdout.split()[:2]
            quota_value = int(quota)
            period_value = int(period)

            verified = (
                quota_value > 0
                and period_value > 0
                and quota_value / period_value <= 0.5
            )
        except (ValueError, IndexError):
            verified = False

        return self._result(
            "cpu_limit",
            (
                AssessmentStatus.PASS
                if verified
                else AssessmentStatus.WARNING
            ),
            (
                "The container reports a CPU quota of at most 0.5 CPU."
                if verified
                else "The expected CPU quota was not demonstrated."
            ),
        )

    def _probe_memory_limit(self) -> CapabilityResult:
        """Verify that the configured memory limit is visible in cgroups."""

        expected_bytes = 128 * 1024 * 1024

        result = self._run_container_probe(
            [
                "sh",
                "-c",
                "cat /sys/fs/cgroup/memory.max",
            ],
            options=["--memory=128m", "--memory-swap=128m"],
        )

        if result.returncode != 0:
            return self._result(
                "memory_limit",
                AssessmentStatus.WARNING,
                "The container memory limit could not be inspected.",
            )

        try:
            actual = int(result.stdout.strip())
            verified = 0 < actual <= expected_bytes
        except ValueError:
            verified = False

        return self._result(
            "memory_limit",
            (
                AssessmentStatus.PASS
                if verified
                else AssessmentStatus.WARNING
            ),
            (
                "The container reports a memory limit of at most 128 MiB."
                if verified
                else "The expected memory limit was not demonstrated."
            ),
        )

    def _probe_process_limit(self) -> CapabilityResult:
        """Verify that the configured PID limit is visible in cgroups."""

        result = self._run_container_probe(
            [
                "sh",
                "-c",
                "cat /sys/fs/cgroup/pids.max",
            ],
            options=["--pids-limit=64"],
        )

        if result.returncode != 0:
            return self._result(
                "process_limit",
                AssessmentStatus.WARNING,
                "The container process limit could not be inspected.",
            )

        try:
            actual = int(result.stdout.strip())
            verified = 0 < actual <= 64
        except ValueError:
            # "max" means no finite limit was demonstrated.
            verified = False

        return self._result(
            "process_limit",
            (
                AssessmentStatus.PASS
                if verified
                else AssessmentStatus.WARNING
            ),
            (
                "The container reports a finite PID limit of at most 64."
                if verified
                else "The expected process limit was not demonstrated."
            ),
        )

    def _probe_docker_socket_isolation(self) -> CapabilityResult:
        """Check that standard Docker socket paths are not exposed."""

        result = self._run_container_probe(
            [
                "sh",
                "-c",
                (
                    "for path in /var/run/docker.sock /run/docker.sock; "
                    "do "
                    'if test -S "$path"; then exit 1; fi; '
                    "done; exit 0"
                ),
            ]
        )

        verified = result.returncode == 0

        return self._result(
            "docker_socket_isolation",
            (
                AssessmentStatus.PASS
                if verified
                else AssessmentStatus.WARNING
            ),
            (
                "The checked standard Docker socket paths are not exposed "
                "as sockets in the container."
                if verified
                else "Docker socket isolation was not demonstrated. "
                "Other socket paths were not assessed."
            ),
        )

    def assess(self) -> BackendReport:
        """Assess Podman controls without making CI execution decisions."""

        if not self.podman:
            results = [
                self._result(
                    "podman_availability",
                    AssessmentStatus.WARNING,
                    "Podman is not installed or is not on PATH.",
                ),
            ]

            for name in (
                "rootless_execution",
                "user_namespace",
                "no_new_privileges",
                "read_only_root_filesystem",
                "network_isolation",
                "cpu_limit",
                "memory_limit",
                "process_limit",
                "docker_socket_isolation",
            ):
                results.append(
                    self._result(
                        name,
                        AssessmentStatus.NOT_ASSESSED,
                        "Podman is unavailable; this control was not assessed.",
                    )
                )

            return BackendReport(capabilities=tuple(results))

        try:
            version = self._run(["--version"])

            if version.returncode != 0:
                return BackendReport(
                    capabilities=(
                        self._result(
                            "podman_availability",
                            AssessmentStatus.WARNING,
                            "The Podman executable was found but did not "
                            "return a successful version result.",
                        ),
                    )
                )

            info = self._run(["info", "--format", "json"])

            if info.returncode != 0:
                return BackendReport(
                    capabilities=(
                        self._result(
                            "podman_availability",
                            AssessmentStatus.WARNING,
                            "Podman is installed but its runtime information "
                            "could not be retrieved.",
                        ),
                    )
                )

            results = [
                self._result(
                    "podman_availability",
                    AssessmentStatus.PASS,
                    f"{version.stdout.strip()}; Podman info succeeded.",
                ),
                self._probe_rootless(),
            ]

            image_result = self._prepare_image()
            results.append(image_result)

            if not self._image_ready:
                for name in (
                    "user_namespace",
                    "no_new_privileges",
                    "read_only_root_filesystem",
                    "network_isolation",
                    "cpu_limit",
                    "memory_limit",
                    "process_limit",
                    "docker_socket_isolation",
                ):
                    results.append(
                        self._result(
                            name,
                            AssessmentStatus.NOT_ASSESSED,
                            "The diagnostic image is unavailable; "
                            "this container-level control was not assessed.",
                        )
                    )

                return BackendReport(capabilities=tuple(results))

            probes = (
                ("user_namespace", self._probe_user_namespace),
                ("no_new_privileges", self._probe_no_new_privileges),
                (
                    "read_only_root_filesystem",
                    self._probe_read_only_rootfs,
                ),
                ("network_isolation", self._probe_network_isolation),
                ("cpu_limit", self._probe_cpu_limit),
                ("memory_limit", self._probe_memory_limit),
                ("process_limit", self._probe_process_limit),
                (
                    "docker_socket_isolation",
                    self._probe_docker_socket_isolation,
                ),
            )

            for name, probe in probes:
                try:
                    results.append(probe())
                except (
                    SandboxBackendError,
                    OSError,
                    subprocess.SubprocessError,
                ) as exc:
                    results.append(
                        self._result(
                            name,
                            AssessmentStatus.WARNING,
                            "The capability probe failed: "
                            f"{type(exc).__name__}.",
                        )
                    )

            return BackendReport(capabilities=tuple(results))

        except (
            SandboxBackendError,
            OSError,
            subprocess.SubprocessError,
        ) as exc:
            return BackendReport(
                capabilities=(
                    self._result(
                        "podman_availability",
                        AssessmentStatus.WARNING,
                        "Podman assessment failed: "
                        f"{type(exc).__name__}.",
                    ),
                )
            )


def log_podman_capability_assessment() -> None:
    """Report Podman capabilities without controlling CI execution."""

    print("\n" + "=" * 60)
    print("KUBAPP PODMAN CAPABILITY ASSESSMENT")
    print("=" * 60, flush=True)

    try:
        backend = PodmanSandboxBackend()
        report = backend.assess()

        print(report.summary(), flush=True)

        if report.has_warnings or report.not_assessed:
            print(
                "[INFO] Some controls are unavailable or could not be "
                "verified. Review the report above.",
                flush=True,
            )

        print(
            "[INFO] Capability assessment completed. "
            "CI will proceed Anyway.",
            flush=True,
        )

    except Exception as exc:
        print(
            "[WARNING] Podman capability assessment failed: "
            f"{type(exc).__name__}: {exc} "
            "CI will proceed Anyway....",
            flush=True,
        )

    print("=" * 60 + "\n", flush=True)
