"""Dispatch dependency staging to runtime-specific managers."""

from __future__ import annotations

from pathlib import Path
from python_mgt import stage_python_dependency
from node_mgt import stage_node_dependency


class DependencyStagingError(RuntimeError):
    """Raised when dependency staging fails."""


def stage_dependency(
    runtime: str,
    *,
    app_name: str,
    component_dir: str | Path,
    manifest: str | Path,
    execution_image: str,
    staging_root: str | Path | None = None,
    lockfile: str | Path | None = None,
) -> Path:
    """Stage dependencies using the selected runtime configuration."""

    if not isinstance(runtime, str) or not runtime.strip():
        raise DependencyStagingError(
            "runtime must be a nonempty string."
        )

    runtime = runtime.strip().lower()

    if runtime == "python":
        return stage_python_dependency(
            app_name=app_name,
            component_dir=component_dir,
            manifest=manifest,
            execution_image=execution_image,
            staging_root=staging_root,
        )

    if runtime == "node":
        if lockfile is None:
            raise DependencyStagingError(
                "Node.js dependency staging requires package-lock.json."
            )

        return stage_node_dependency(
            app_name=app_name,
            component_dir=component_dir,
            manifest=manifest,
            lockfile=lockfile,
            execution_image=execution_image,
            staging_root=staging_root,
        )

    raise DependencyStagingError(
        f"Dependency staging is not implemented for runtime {runtime!r}."
    )
