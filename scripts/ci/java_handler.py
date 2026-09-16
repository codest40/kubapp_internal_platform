import subprocess
import os
from reuse import get_latest_commit_id
from command_policy import ensure_command_is_safe

class JavaHandler:
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
            f"[{self.app_name}] Installing Java dependencies..."
        )

        if self.manifest.name == "pom.xml":
            command = [
                "mvn",
                "dependency:resolve",
            ]

        elif self.manifest.name in (
            "build.gradle",
            "build.gradle.kts",
        ):
            command = [
                "./gradlew",
                "dependencies",
            ]

        else:
            raise RuntimeError(
                f"Unsupported Java manifest: "
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
        print(
            f"[{self.app_name}] Started Linting......"
        )

        command = self.ensure_var_exist("lint", "lint")
        command = ensure_command_is_safe(command, "java")
        subprocess.run(
            command,
            cwd=self.app_dir,
            check=True,
        )

        print(f"[{self.app_name}] Lint passed successfully")

    def security_analysis(self):
        print(
            f"[{self.app_name}] "
            f"Started Security Analysis......"
        )

        command = self.ensure_var_exist("security_analysis", "security")
        command = ensure_command_is_safe(command, "java")
        sec_var = self.ci_commands.get("security_env", [])
        if sec_var:
          for a in sec_var:
            var = os.getenv(a)
            if not var:
                raise RuntimeError(
                    f"[{self.app_name}] "
                    f"SECURITY GATE FAILED: NVD_API_KEY is required "
                    f"for OWASP Dependency-Check. "
                    f"'security_env' is detected. Remove it if NOT Neded.")

        subprocess.run( command, cwd=self.app_dir, check=True, )
        print(
            f"[{self.app_name}] "
            f"Security Analysis passed successfully"
        )

    def unit_tests(self):
        print(
            f"[{self.app_name}] "
            f"Started Unit Tests......"
        )

        command = self.ensure_var_exist("unit_tests", "test")
        command = ensure_command_is_safe(command, "java")
        subprocess.run(
            command,
            cwd=self.app_dir,
            check=True,
        )

        print(
            f"[{self.app_name}] "
            f"Unit Tests passed successfully"
        )


    def build_from_dockerfile(self):
        if not self.dockerfile:
            print(
                f"[{self.app_name}] "
                f"No Dockerfile found. "
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
            "docker", "build", "-t", image_name,
            "-f", str(self.dockerfile), str(self.app_dir), ]
        subprocess.run(command, check=True,)
        print(
            f"[{self.app_name}] "
            f"Docker Build passed successfully"
        )
        return image_name
