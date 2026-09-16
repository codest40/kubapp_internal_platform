import subprocess
import sys
from reuse import get_latest_commit_id
from command_policy import ensure_command_is_safe

class PythonHandler:
    def __init__(
        self, app_name=None, manifest=None, dockerfile=False,
        extra_data=None, ci_commands=None,
    ):
        self.manifest = manifest
        self.dockerfile = dockerfile
        self.app_dir = manifest.parent
        self.app_name = app_name
        self.component_name = manifest.parent.name
        self.extra_data = extra_data or {}
        self.ci_commands = ci_commands or {}

    def ensure_var_exist(self, function, command):
        result = self.ci_commands.get(command)

        if not result:
            function = function.upper()
            raise RuntimeError(
                f"[{self.app_name}] {function} GATE FAILED: "
                f"Command is unavailable or not correctly configured."
            )

        print(
            f"[{self.app_name}] {function.upper()} command: "
            f"{' '.join(result)}"
        )

        return result

    def install_dependencies(self):
        print(
            f"[{self.app_name}] Installing Python dependencies..."
        )

        if self.manifest.name == "requirements.txt":
            command = [
                sys.executable,
                "-m",
                "pip",
                "install",
                "-r",
                str(self.manifest),
            ]
        elif self.manifest.name == "pyproject.toml":
            command = [
                sys.executable,
                "-m",
                "pip",
                "install",
                ".",
            ]
        else:
            raise RuntimeError(
                f"Unsupported Python manifest: "
                f"{self.manifest.name}"
            )

        subprocess.run(
            command,
            cwd=self.app_dir,
            check=True,
        )

        print(
            f"[{self.app_name}] Dependencies installed successfully"
        )

    def lint(self):
        print(f"[{self.app_name}] Started Linting......")

        command = self.ensure_var_exist(
            "lint",
            "lint",
        )
        command = ensure_command_is_safe(command, "python")
        subprocess.run(
            command,
            cwd=self.app_dir,
            check=True,
        )

        print(
            f"[{self.app_name}] Lint passed successfully"
        )

    def security_analysis(self):
        print(
            f"[{self.app_name}] Started Security Analysis......"
        )

        command = self.ensure_var_exist(
            "security_analysis",
            "security",
        )
        command = ensure_command_is_safe(command, "python")
        subprocess.run(
            command,
            cwd=self.app_dir,
            check=True,
        )

        print(
            f"[{self.app_name}] Security Analysis passed successfully"
        )

    def unit_tests(self):
        print(f"[{self.app_name}] Started Unit Tests......")

        command = self.ensure_var_exist(
            "unit_tests",
            "test",
        )
        command = ensure_command_is_safe(command, "python")
        subprocess.run(
            command,
            cwd=self.app_dir,
            check=True,
        )

        print(
            f"[{self.app_name}] Unit Tests passed successfully"
        )

    def build_from_dockerfile(self):
        if not self.dockerfile:
            print(
                f"[{self.app_name}] No Dockerfile found. "
                f"Skipping Docker build..."
            )
            return

        print(
            f"[{self.app_name}] Building Docker image "
            f"Via Dockerfile......"
        )

        id = get_latest_commit_id()
        image_name = f"{self.app_name}:{id}"
        subprocess.run(
            [
                "docker",
                "build",
                "-t",
                image_name,
                "-f",
                str(self.dockerfile),
                ".",
            ],
            cwd=self.app_dir,
            check=True,
        )

        subprocess.run(
            [
                "docker",
                "image",
                "inspect",
                image_name,
            ],
            check=True,
        )

        print(
            f"[{self.app_name}] Docker image built successfully: "
            f"{image_name}"
        )
        return image_name

