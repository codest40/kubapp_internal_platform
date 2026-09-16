import subprocess
import requests
import time

class ContainerManager:

    def validate(self, value, message):
        if not value:
            raise RuntimeError(message)

    def start_container(self, image_name, container_name, host_port, container_port):
        self.validate(image_name, "Image name is required to start container")
        self.validate(container_name, "Container name is required to start container")
        self.validate(host_port, "Host port is required to start container")
        self.validate(container_port, "Container port is required to start container")

        subprocess.run(
            [
                "docker", "run", "-d",
                "--name", container_name,
                "-p", f"{host_port}:{container_port}",
                image_name,
            ],
            check=True,
        )

        print(
            f"Container started successfully: "
            f"{container_name}"
        )
        return container_name

    def test_container(self,
          container_name, host_port, endpoint, status=200,
          retries=10, delay=2,
        ):
        self.validate(container_name, "Container name is required to test container")
        self.validate(endpoint, "Container endpoint is required to test container")
        self.validate(host_port, "Host port is required to test container")

        url = f"http://localhost:{host_port}/{endpoint.lstrip('/')}"
        print(f"[{container_name}]: Testing {url}")

        for attempt in range(1, retries + 1):
            try:
                response = requests.get(url, timeout=5,)
                if response.status_code == status:
                    print(
                        f"Application health check passed: "
                        f"{url} returned HTTP "
                        f"{response.status_code}"
                    )
                    return True

                print(
                    f"[{container_name}] Health check "
                    f"attempt {attempt}/{retries} returned "
                    f"HTTP {response.status_code}"
                )

            except requests.RequestException as exc:
                print(
                    f"[{container_name}] Health check "
                    f"attempt {attempt}/{retries} failed: "
                    f"{exc}"
                )

            time.sleep(delay)

        app_log = subprocess.run(
            ["docker", "logs", container_name],
            capture_output=True,
            text=True,
        )

        print(
            f"[{container_name}] logs:\n"
            f"{app_log.stdout}"
        )

        raise RuntimeError(
            f"Application health check failed: {url}"
        )

    def stop_container(self, container_name):
        self.validate(container_name,
              "Container name is required to stop container")

        subprocess.run(
            ["docker", "stop", container_name],
            check=True,
        )

        print(
            f"Container stopped successfully: "
            f"{container_name}"
        )
        return container_name


    def remove_container(self, container_name):
        self.validate(container_name,
            "Container name is required to remove container")

        subprocess.run(
            ["docker", "rm", container_name],
            check=True,
        )

        print(
            f"Container removed successfully: "
            f"{container_name}"
        )
        return container_name
