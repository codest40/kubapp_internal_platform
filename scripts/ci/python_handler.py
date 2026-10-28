import sys

from reuse import (
    get_latest_commit_id,
    run_platform_command,
    run_component_command,
    collect_content,
)
from command_policy import ensure_command_is_safe
from dependency_mgt import stage_dependency
from run_ci import CIRunner
from platform_decision import KUBAPP_DECISION
from ai_analysis import analyze_data

class PythonHandler:
    def __init__(
        self, app_name=None, component_dir=None, parent_dir=None,
        runtime=None, manifest=None, extra_manifests=None, dockerfile=None,
        ci_commands=None, extra_ci_commands=None, extra_ci_config=None,
        security_env=None, env=None, component_environment=None,
    ):
        self.app_name = app_name
        self.app_dir = component_dir
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
        self.execution_image = (
           component_environment.execution_image
           if component_environment is not None
           else None
        )
        self.env = (
            component_environment.component_env.copy()
            if component_environment is not None
            else (env.copy() if env is not None else {})
        )

    def ensure_var_exist(self, function, command):
        result = self.ci_commands.get(command)
        if not result:
            raise RuntimeError(
                f"[{self.app_name}] {function.upper()} GATE FAILED: "
                "Command is unavailable or not correctly configured."
            )
        print(
            f"[{self.app_name}] {function.upper()} command: "
            f"{' '.join(result)}"
        )
        return result

    def install_dependencies(self):
        allowed_manifests = ["requirements.txt", "pyproject.toml"]
        if self.manifest.name not in allowed_manifests:
            raise RuntimeError(
                f"Unsupported Python manifest: {self.manifest.name}"
            )
        if self.execution_image is None:
            raise RuntimeError(
                f"[{self.app_name}] No Python execution image configured."
            )
        print(
            f"[{self.app_name}] Preparing Python dependencies "
            "in the execution image..."
        )

        result = analyze_data({
                "app_name": self.app_name,
                "artifact_type": "module",
                "script_content": collect_content(
                    self.manifest, allowed_root=self.app_dir
                ),
                "component_dir": str(self.app_dir),
                "runtime": self.runtime,
        })
        KUBAPP_DECISION(result)

        self.staged_dependencies = stage_dependency(
            runtime="python",
            app_name=self.app_name,
            component_dir=self.app_dir,
            manifest=self.manifest,
            execution_image=self.execution_image,
        )
        if self.component_environment is None:
            raise RuntimeError(
                f"[{self.app_name}] Component environment is unavailable."
            )

        self.component_environment.set_dependency_environment(
            self.staged_dependencies
        )
        print(
            f"[{self.app_name}] Python dependency environment prepared: "
            f"{self.staged_dependencies}"
        )

    def lint(self):
        print(f"[{self.app_name}] Started Linting......")

        command = self.ensure_var_exist("lint", "lint")
        command = ensure_command_is_safe(command, "python")
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
        command = ensure_command_is_safe(command, "python")

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
        command = ensure_command_is_safe(command, "python")

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

        print(f"[{self.app_name}] Building Docker image via Dockerfile......")
        commit_id = get_latest_commit_id()
        image_name = f"{self.app_name}:{commit_id}"

        run_platform_command(
            [
                "docker", "build", "-t", image_name,
                "-f", str(self.dockerfile), str(self.app_dir),
            ],
            label=f"[{self.app_name}] Docker Build",
            env=self.env,
        )

        run_platform_command(
            ["docker", "image", "inspect", image_name],
            label=f"[{self.app_name}] Docker Image Inspect",
        )

        print(
            f"[{self.app_name}] Docker image built successfully: "
            f"{image_name}"
        )
        return image_name

    def run_ci(self, use_script=False, ci_scripts=None):
        runner = CIRunner(
            handler=self,
            use_script=use_script,
            ci_scripts=ci_scripts,
        )
        return runner.run()
