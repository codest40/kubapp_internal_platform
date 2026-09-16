import subprocess
from reuse import get_timestamp

class AppBuilder:
    def tag(self, image, user):
        if not user or not image:
          raise RuntimeError(
                "Image and Docker Hub user are required for tagging"
            )
        TS = get_timestamp()
        tagged_image = f"{user}/{image}-{TS}"
        subprocess.run(
            ["docker", "tag", image, tagged_image],
            check=True, )
        print(
            f"Docker image tagged successfully: "
            f"{tagged_image}"
        )
        return tagged_image

    def validate(self,
          app_dir=None, app_name=None, image=None, user=None, passwd=None
        ):
        reasons = []
        success = True
        if not user:
            success = False
            reasons.append(f"No value set for USER")
        if not passwd:
            success = False
            reasons.append(f"No value set for PASSWORD")


        if not app_dir or not app_dir.is_dir():
            success = False
            reasons.append(
                f"Invalid application directory: {app_dir}"
            )
        elif not any(app_dir.iterdir()):
            success = False
            reasons.append(
                f"Application directory is empty: {app_dir}"
            )

        if not app_name or "_app" not in app_name:
            success = False
            reasons.append(
                f"Invalid application name: {app_name}"
            )

        if not image:
            success = False
            reasons.append("No Docker image provided")
        else:
            result = subprocess.run(
                ["docker", "image", "inspect", image],
                capture_output=True,
                text=True,
            )

            if result.returncode != 0:
                success = False
                reasons.append(
                    f"Image validation failed: {image}"
                )

        if not success:
            raise RuntimeError(
                f"Validation failed for {app_name} | "
                f"Directory: {app_dir} | "
                f"REASONS: {reasons}" )

        print(
            f"Docker image validation passed: {image}"
        )
        return True

    def authenticate(self, user, passwd):
        if not user or not passwd:
            raise RuntimeError(
                "Docker Hub USER and PASSWORD are required"
            )
        result = subprocess.run(
            [ "docker", "login", "--username", user, "--password-stdin", ],
            input=passwd,
            text=True,
            capture_output=True,
        )
        if result.returncode != 0:
            raise RuntimeError(
              f"Docker Hub authentication failed for {user}: "
              f"{result.stderr.strip()}"
            )
        print(
            f"Docker Hub authentication successful for {user}"
        )
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
