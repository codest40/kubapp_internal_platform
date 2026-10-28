# `app_validator.py` — Docker Image Validation and Publication

## Purpose

`app_validator.py` defines the `ValidateApp` class, which handles Docker image tagging, local image inspection, Docker Hub authentication, and image publication.

It provides image-related operations for the CI orchestration layer. It does not independently validate application configuration, build images, or test application health.

## Responsibilities

| Method | Responsibility | Behavior |
|---|---|---|
| `__init__()` | Store application context | Accepts the application name, directory, runtime, manifest, and Dockerfile. |
| `tag(image, user)` | Create a registry image tag | Requires an image reference and username, generates a timestamped tag, and executes `docker tag`. |
| `validate_image(image)` | Inspect a local Docker image | Runs `docker image inspect` and raises an error if inspection fails. |
| `authenticate(username, password)` | Authenticate with Docker Hub | Supplies the password through standard input to `docker login --password-stdin`. |
| `push(image)` | Publish an image | Runs `docker push` and raises an error if publication fails. |

## 1. Image Tagging

The `tag()` method requires both an image reference and a Docker Hub username.

It extracts the final image name from the supplied reference, separates any existing tag, and appends a timestamp.

For example, an image reference such as:

`localapp:latest`

could become:

`dockeruser/localapp:latest-<timestamp>`

If the input has no existing tag, the generated reference uses the timestamp as its tag:

`dockeruser/localapp:<timestamp>`

The timestamp comes from `get_timestamp()` in `reuse.py`.

The method then executes:

`docker tag <source-image> <tagged-image>`

The subprocess uses `check=True`, so a nonzero exit status raises a `subprocess.CalledProcessError`. If tagging succeeds, the method logs the resulting reference and returns it.

**Important:** This method creates a tag for an existing local image. It does not build the image or publish it to a registry.

## 2. Local Image Validation

The `validate_image()` method first checks that an image reference was provided. It then runs:

`docker image inspect <image>`

Unlike `tag()`, this method does not use `check=True`. It inspects the subprocess return code and raises a `RuntimeError` if the command fails. The error includes the image reference and Docker's standard-error output.

On success, the method logs the result and returns `True`.

A successful inspection confirms that Docker can inspect the referenced image locally. It does **not** establish that:

- The application starts successfully.
- The application responds correctly to requests.
- The container passes its configured health checks.
- The image is free from vulnerabilities.
- The image has been published to a registry.

Those concerns require separate checks.

## 3. Docker Hub Authentication

The `authenticate()` method requires both a username and a password.

It executes Docker login using:

`docker login --username <username> --password-stdin`

The password is supplied through the subprocess's standard input rather than being included directly in the command arguments.

If Docker login returns a nonzero exit code, the method raises a `RuntimeError` containing the username and standard-error output. Otherwise, it logs success and returns `True`.

Using `--password-stdin` reduces the risk of exposing the password through command-line argument inspection. It does not, by itself, guarantee secure handling of credentials throughout the entire CI environment.

## 4. Image Publication

The `push()` method requires an image reference and executes:

`docker push <image>`

It checks the subprocess return code. If publication fails, it raises a `RuntimeError` containing the image reference and standard-error output.

If publication succeeds, the method logs success and returns the image reference.

This method does not independently verify the image's contents or confirm that a deployment has successfully pulled and started the published image.

## 5. Error Handling

The methods use two subprocess error-handling patterns:

- **`tag()`** uses `check=True`. A failed Docker command raises `subprocess.CalledProcessError`.
- **`validate_image()`, `authenticate()`, and `push()`** inspect the returned process status and raise `RuntimeError` when the operation fails.

Missing required arguments also result in `RuntimeError`.

These exceptions allow the calling CI layer to detect failures and decide whether the component can proceed to subsequent stages.

The methods do not implement retries or recovery themselves.

## 6. Position in the CI Flow

At the image lifecycle stage, the expected sequence is:

1. A runtime handler builds the Docker image.
2. `tag()` creates a timestamped image reference under the configured Docker Hub username.
3. `validate_image()` checks that Docker can inspect the tagged image locally.
4. The orchestration layer starts a temporary container and checks its configured health endpoints.
5. The temporary container is stopped and removed.
6. `authenticate()` authenticates with Docker Hub.
7. `push()` publishes the image.
8. The orchestration layer records the successful component result for downstream processing.

The exact order and failure behavior depend on the caller in `dependency_abstractor.py`.

## 7. Security and Scope

Several boundaries are important:

- **Image operations are not application validation.** Manifest validation and runtime checks are handled elsewhere in the CI pipeline.
- **Image inspection is not a security scan.** This class does not scan image layers, dependencies, or operating-system packages for vulnerabilities.
- **Health checking is separate.** `container.py` handles container startup and configured HTTP endpoint checks.
- **Registry authentication is separate from image validation.** A locally inspectable image may still fail to authenticate or publish.
- **Subprocess execution relies on Docker.** This class invokes Docker commands directly; it does not itself establish a sandbox for Docker operations.
- **Credentials require broader protection.** `--password-stdin` avoids placing the password in the command arguments, but credential storage, environment handling, and runner access must be protected by the surrounding CI design.

## Important Distinction

Despite the class name `ValidateApp`, `ValidateApp` currently focuses on Docker image lifecycle operations: tagging, local inspection, registry authentication, and publication.
It does not independently validate application manifests, enforce component command policies, perform AI-assisted artifact assessment, or verify application health.
