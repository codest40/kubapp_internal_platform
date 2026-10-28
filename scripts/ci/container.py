import subprocess
import time
import requests


class ContainerManager:

    def validate(self, value, message):
        if not value:
            raise RuntimeError(message)

    def start_container(
        self,
        image,
        container_name,
        app_port,
        host_port,
    ):
        self.validate(image, "Image name is required to start container")
        self.validate(
            container_name,
            "Container name is required to start container",
        )
        self.validate(app_port, "Application port is required to start container")
        self.validate(host_port, "Host port is required to start container")

        subprocess.run(
            [
                "docker",
                "run",
                "-e",
                "CI=true",
                "-d",
                "--name",
                container_name,
                "-p",
                f"{host_port}:{app_port}",
                image,
            ],
            check=True,
            capture_output=True,
            text=True,
        )

        print(f"Container started successfully: {container_name}")
        return container_name

    def test_container(
        self,
        container,
        host_port,
        endpoints,
        expected_status=200,
        retries=10,
        delay=2,
    ):
        self.validate(container, "Container name is required to test container")
        self.validate(host_port, "Host port is required to test container")
        self.validate(endpoints, "Container endpoints are required to test container")

        if isinstance(endpoints, str):
            endpoints = [endpoints]

        for endpoint in endpoints:
            self.validate(endpoint, "Container endpoint cannot be empty")

            url = f"http://localhost:{host_port}/{str(endpoint).lstrip('/')}"
            print(f"[{container}]: Testing {url}")

            for attempt in range(1, retries + 1):
                try:
                    response = requests.get(url, timeout=5)

                    if response.status_code == expected_status:
                        print(
                            f"Application health check passed: {url} "
                            f"returned HTTP {response.status_code}"
                        )
                        break

                    print(
                        f"[{container}] Health check attempt "
                        f"{attempt}/{retries} returned HTTP "
                        f"{response.status_code}"
                    )

                except requests.RequestException as exc:
                    print(
                        f"[{container}] Health check attempt "
                        f"{attempt}/{retries} failed: {exc}"
                    )

                if attempt < retries:
                    time.sleep(delay)
            else:
                app_log = subprocess.run(
                    ["docker", "logs", container],
                    capture_output=True,
                    text=True,
                )

                print(f"[{container}] logs:\n{app_log.stdout}")
                if app_log.stderr:
                    print(f"[{container}] log errors:\n{app_log.stderr}")

                raise RuntimeError(
                    f"Application health check failed: {url}"
                )

        return True

    def stop_container(self, container):
        self.validate(
            container,
            "Container name is required to stop container",
        )

        subprocess.run(
            ["docker", "stop", container],
            check=True,
            capture_output=True,
            text=True,
        )

        print(f"Container stopped successfully: {container}")
        return container

    def remove_container(self, container):
        self.validate(
            container,
            "Container name is required to remove container",
        )

        subprocess.run(
            ["docker", "rm", container],
            check=True,
            capture_output=True,
            text=True,
        )

        print(f"Container removed successfully: {container}")
        return container
