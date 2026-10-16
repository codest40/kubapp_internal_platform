import subprocess

from reuse import get_timestamp


class ValidateApp:

    def __init__(
        self,
        app_name=None,
        app_dir=None,
        runtime=None,
        manifest=None,
        dockerfile=None,
    ):
        self.app_name = app_name
        self.app_dir = app_dir
        self.runtime = runtime
        self.manifest = manifest
        self.dockerfile = dockerfile

    def tag(self, image, user):
        if not user or not image:
            raise RuntimeError(
                "Image and Docker Hub user are required for tagging"
            )

        timestamp = get_timestamp()
        image_name = image.rsplit("/", 1)[-1]
        image_name, separator, existing_tag = image_name.partition(":")

        tag_suffix = f"{existing_tag}-{timestamp}" if separator else timestamp
        tagged_image = f"{user}/{image_name}:{tag_suffix}"

        subprocess.run(
            ["docker", "tag", image, tagged_image],
            check=True,
            capture_output=True,
            text=True,
        )

        print(f"Docker image tagged successfully: {tagged_image}")
        return tagged_image

    def validate_image(self, image):
        if not image:
            raise RuntimeError("No Docker image provided for validation")

        result = subprocess.run(
            ["docker", "image", "inspect", image],
            capture_output=True,
            text=True,
        )

        if result.returncode != 0:
            raise RuntimeError(
                f"Image validation failed: {image} | "
                f"REASON: {result.stderr.strip()}"
            )

        print(f"Docker image validation passed: {image}")
        return True

    def authenticate(self, username=None, password=None):
        if not username or not password:
            raise RuntimeError(
                "Docker Hub username and password are required"
            )

        result = subprocess.run(
            [
                "docker",
                "login",
                "--username",
                username,
                "--password-stdin",
            ],
            input=password,
            text=True,
            capture_output=True,
        )

        if result.returncode != 0:
            raise RuntimeError(
                f"Docker Hub authentication failed for {username}: "
                f"{result.stderr.strip()}"
            )

        print(f"Docker Hub authentication successful for {username}")
        return True

    def push(self, image):
        if not image:
            raise RuntimeError("Docker image is required for push")

        print(f"Pushing Docker image to Docker Hub: {image}")

        result = subprocess.run(
            ["docker", "push", image],
            capture_output=True,
            text=True,
        )

        if result.returncode != 0:
            raise RuntimeError(
                f"Docker image push failed: {image} | "
                f"REASON: {result.stderr.strip()}"
            )

        print(f"Docker image pushed successfully: {image}")
        return image
