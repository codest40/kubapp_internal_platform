import os
from reuse import get_latest_commit_id, run_command
from command_policy import ensure_command_is_safe
from run_ci import CIRunner


class JavaHandler:
    def __init__(
        self, app_name=None, component_dir=None, parent_dir=None,
        runtime=None, manifest=None, extra_manifests=None, dockerfile=None,
        ci_commands=None, extra_ci_commands=None, extra_ci_config=None,
        security_env=None, env=None,
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
        self.env = os.environ.copy() if env is None else env.copy()

    def ensure_var_exist(self, function, command):
        result = self.ci_commands.get(command)

        if not result:
            raise RuntimeError(
                f"[{self.app_name}] {function.upper()} GATE FAILED: "
                f"Command is unavailable or not correctly configured."
            )

        print(
            f"[{self.app_name}] {function.upper()} command: "
            f"{' '.join(result)}"
        )

        return result

    def install_dependencies(self):
        print(f"[{self.app_name}] Installing Java dependencies...")

        if self.manifest.name == "pom.xml":
            command = ["mvn", "dependency:resolve"]
        elif self.manifest.name in ("build.gradle", "build.gradle.kts"):
            command = ["./gradlew", "dependencies"]
        else:
            raise RuntimeError(
                f"Unsupported Java manifest: {self.manifest.name}"
            )

        run_command(
            command,
            cwd=self.app_dir,
            label=f"[{self.app_name}] Installing dependencies",
            env=self.env,
        )

        print(f"[{self.app_name}] Dependencies installed successfully")

    def lint(self):
        print(f"[{self.app_name}] Started Linting......")

        command = self.ensure_var_exist("lint", "lint")
        command = ensure_command_is_safe(command, "java")

        run_command(
            command,
            cwd=self.app_dir,
            label=f"[{self.app_name}] Lint",
            env=self.env,
        )

        print(f"[{self.app_name}] Lint passed successfully")

    def security_analysis(self):
        print(f"[{self.app_name}] Started Security Analysis......")

        command = self.ensure_var_exist("security_analysis", "security")
        command = ensure_command_is_safe(command, "java")
        run_command(
            command,
            cwd=self.app_dir,
            label=f"[{self.app_name}] Security Analysis",
            env=self.env,
        )

        print(f"[{self.app_name}] Security Analysis passed successfully")

    def unit_tests(self):
        print(f"[{self.app_name}] Started Unit Tests......")

        command = self.ensure_var_exist("unit_tests", "test")
        command = ensure_command_is_safe(command, "java")

        run_command(
            command,
            cwd=self.app_dir,
            label=f"[{self.app_name}] Unit Tests",
            env=self.env,
        )

        print(f"[{self.app_name}] Unit Tests passed successfully")

    def build_from_dockerfile(self):
        if not self.dockerfile:
            print(
                f"[{self.app_name}] No Dockerfile found. "
                f"Skipping Docker build..."
            )
            return None

        print(f"[{self.app_name}] Started Docker Build......")

        commit_id = get_latest_commit_id()
        image_name = f"{self.app_name}:{commit_id}"
        run_command(
            [
                "docker", "build", "-t", image_name,
                "-f", str(self.dockerfile), str(self.app_dir),
            ],
            label=f"[{self.app_name}] Docker Build",
            env=self.env,

        )

        run_command(
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
