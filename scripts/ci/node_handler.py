from pathlib import Path

from reuse import (
    get_latest_commit_id,
    run_platform_command,
    run_component_command,
    collect_content,
)
from command_policy import ensure_command_is_safe
from dependency_mgt import stage_dependency
from platform_decision import KUBAPP_DECISION
from ai_analysis import analyze_data
from run_ci import CIRunner


class NodeHandler:
    def __init__(
        self,
        app_name=None,
        component_dir=None,
        parent_dir=None,
        runtime=None,
        manifest=None,
        extra_manifests=None,
        dockerfile=None,
        ci_commands=None,
        extra_ci_commands=None,
        extra_ci_config=None,
        security_env=None,
        env=None,
        component_environment=None,
    ):
        self.app_name = app_name
        self.app_dir = Path(component_dir).resolve() if component_dir else None
        self.parent_dir = parent_dir
        self.runtime = runtime
        self.manifest = manifest
        self.extra_manifests = extra_manifests or []
        self.dockerfile = dockerfile
        self.ci_commands = ci_commands or {}
        self.extra_ci_commands = extra_ci_commands or {}
        self.extra_ci_config = extra_ci_config or {}
        self.security_env = security_env or []
        self.component_environment = component_environment

        self.env = (
            component_environment.component_env.copy()
            if component_environment is not None
            else (env.copy() if env is not None else {})
        )

        self.execution_image = (
            component_environment.execution_image
            if component_environment is not None
            else None
        )

        self.staged_dependencies = None

    def ensure_var_exist(self, function, command):
        result = self.ci_commands.get(command)

        if not result:
            raise RuntimeError(
                f"[{self.app_name}] {function.upper()} GATE FAILED: "
                "Command is unavailable or not correctly configured."
            )

        if (
            not isinstance(result, list)
            or not result
            or not all(
                isinstance(item, str) and item.strip()
                for item in result
            )
        ):
            raise RuntimeError(
                f"[{self.app_name}] {function.upper()} GATE FAILED: "
                "Configured command must be a nonempty list of strings."
            )

        print(
            f"[{self.app_name}] {function.upper()} command: "
            f"{' '.join(result)}"
        )

        return result

    def install_dependencies(self):
        """Stage npm dependencies in the controlled Node.js environment."""
        if self.app_dir is None or not self.app_dir.is_dir():
            raise RuntimeError(
                f"[{self.app_name}] Application directory is unavailable."
            )

        if self.manifest is None:
            raise RuntimeError(
                f"[{self.app_name}] package.json manifest is unavailable."
            )
        package_manifest = Path(self.manifest)
        if not package_manifest.is_absolute():
            package_manifest = self.app_dir / package_manifest
        if not package_manifest.is_file():
            raise RuntimeError(
                f"[{self.app_name}] Missing package.json. "
                "Node.js dependency staging cannot continue."
            )

        extra_manifests = [
            Path(item) for item in self.extra_manifests
        ]

        package_lock = next(
            (
                item for item in extra_manifests
                if item.name == "package-lock.json"
            ),
            None,
        )

        if package_lock is None:
            raise RuntimeError(
                f"[{self.app_name}] package-lock.json was not supplied "
                "through EXTRA_MANIFESTS."
            )

        if not package_lock.is_file():
            raise RuntimeError(
                f"[{self.app_name}] Missing package-lock.json. "
                "KUBAPP requires a committed npm lockfile and does not "
                "fall back to npm install."
            )

        if self.execution_image is None:
            raise RuntimeError(
                f"[{self.app_name}] No Node.js execution image configured."
            )

        if self.component_environment is None:
            raise RuntimeError(
                f"[{self.app_name}] Component environment is unavailable."
            )

        print(
            f"[{self.app_name}] Preparing npm dependencies "
            "in the controlled Node.js execution environment..."
        )

        result = analyze_data({
                "app_name": self.app_name,
                "artifact_type": "module",
                "script_content": collect_content(
                    package_manifest, allowed_root=self.app_dir
                ),
                "component_dir": str(self.app_dir),
                "runtime": self.runtime,
        })
        KUBAPP_DECISION(result)
        self.staged_dependencies = stage_dependency(
            runtime="node",
            app_name=self.app_name,
            component_dir=self.app_dir,
            manifest=package_manifest,
            lockfile=package_lock,
            execution_image=self.execution_image,
        )

        self.component_environment.set_dependency_environment(
            self.staged_dependencies
        )

        print(
            f"[{self.app_name}] npm dependency environment prepared: "
            f"{self.staged_dependencies}"
        )

    def lint(self):
        print(f"[{self.app_name}] Started Linting......")

        command = self.ensure_var_exist("lint", "lint")
        command = ensure_command_is_safe(command, "node")

        run_component_command(
            command,
            component_environment=self.component_environment,
            cwd=self.app_dir,
            label=f"[{self.app_name}] Lint",
        )

        print(f"[{self.app_name}] Lint passed successfully")

    def security_analysis(self):
        print(f"[{self.app_name}] Started Security Analysis......")

        command = self.ensure_var_exist("security_analysis", "security")
        command = ensure_command_is_safe(command, "node")

        run_component_command(
            command,
            component_environment=self.component_environment,
            cwd=self.app_dir,
            label=f"[{self.app_name}] Security Analysis",
        )

        print(f"[{self.app_name}] Security Analysis passed successfully")

    def unit_tests(self):
        print(f"[{self.app_name}] Started Unit Tests......")

        command = self.ensure_var_exist("unit_tests", "test")
        command = ensure_command_is_safe(command, "node")

        run_component_command(
            command,
            component_environment=self.component_environment,
            cwd=self.app_dir,
            label=f"[{self.app_name}] Unit Tests",
        )

        print(f"[{self.app_name}] Unit Tests passed successfully")

    def build_from_dockerfile(self):
        if not self.dockerfile:
            print(
                f"[{self.app_name}] No Dockerfile found. "
                "Skipping Docker build..."
            )
            return None

        result = analyze_data({
                "app_name": self.app_name,
                "artifact_type": "dockerfile",
                "script_content": collect_content(
                    self.dockerfile, allowed_root=self.app_dir
                ),
                "component_dir": str(self.app_dir),
                "runtime": self.runtime,
        })
        KUBAPP_DECISION(result)

        print(f"[{self.app_name}] Started Docker Build......")
        commit_id = get_latest_commit_id()
        image_name = f"{self.app_name}:{commit_id}"

        run_platform_command(
            [
                "docker",
                "build",
                "-t",
                image_name,
                "-f",
                str(self.dockerfile),
                str(self.app_dir),
            ],
            label=f"[{self.app_name}] Docker Build",
            env=self.env,
        )

        run_platform_command(
            ["docker", "image", "inspect", image_name],
            label=f"[{self.app_name}] Docker Image Inspect",
        )

        print(f"[{self.app_name}] Docker Build passed successfully")
        return image_name

    def run_ci(self, use_script=False, ci_scripts=None):
        runner = CIRunner(
            handler=self,
            use_script=use_script,
            ci_scripts=ci_scripts,
        )
        return runner.run()
