import subprocess
from reuse import get_latest_commit_id
from command_policy import ensure_command_is_safe

class NodeHandler:
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
            f"[{self.app_name}] Installing Node dependencies..."
        )

        package_lock = self.extra_data.get("package-lock.json")

        if package_lock:
            command = [
                "npm",
                "ci",
            ]
            print(
                f"[{self.app_name}] Installing with package-lock.json"
            )
        else:
            command = [
                "npm",
                "install",
            ]
            print(
                f"[{self.app_name}] Installing without package-lock.json"
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
        print(
            f"[{self.app_name}] Started Linting......"
        )

        command = self.ensure_var_exist(
            "lint",
            "lint",
        )

        command = ensure_command_is_safe(command, "node")
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
        command = ensure_command_is_safe(command, "node")
        subprocess.run(
            command,
            cwd=self.app_dir,
            check=True,
        )

        print(
            f"[{self.app_name}] Security Analysis passed successfully"
        )

    def unit_tests(self):
        print(
            f"[{self.app_name}] Started Unit Tests......"
        )

        command = self.ensure_var_exist(
            "unit_tests",
            "test",
        )
        command = ensure_command_is_safe(command, "node")
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
            f"[{self.app_name}] "
            f"Started Docker Build......"
        )

        id = get_latest_commit_id()
        image_name = f"{self.app_name}:{id}"
        command = [
            "docker",
            "build",
            "-t",
            image_name,
            "-f",
            str(self.dockerfile),
            str(self.app_dir),
        ]

        subprocess.run(
            command,
            check=True,
        )

        print(
            f"[{self.app_name}] "
            f"Docker Build passed successfully"
        )
        return image_name
