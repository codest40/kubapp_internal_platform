# `container.py` — Container Startup and Health Checks

## Purpose

`container.py` defines the `ContainerManager` class, which starts application containers, tests their HTTP endpoints, collects logs when health checks fail, and provides methods to stop and remove containers.

It is used during CI to verify that a built Docker image can start and respond to configured HTTP health checks before the image is published.

## Responsibilities

| Method | Responsibility | Behavior |
|---|---|---|
| `validate(value, message)` | Validate required arguments | Raises `RuntimeError` when a required value is falsy. |
| `start_container()` | Start a container | Runs the image in detached mode, sets `CI=true`, and maps the host port to the application port. |
| `test_container()` | Test application endpoints | Sends HTTP GET requests, retries unsuccessful checks, collects logs on failure, and raises an error if an endpoint never passes. |
| `stop_container()` | Stop a running container | Executes `docker stop`. |
| `remove_container()` | Remove a stopped container | Executes `docker rm`. |

## 1. Starting a Container

The `start_container()` method requires:

- An image reference.
- A container name.
- An application port.
- A host port.

It starts the container using Docker with these options:

- `-e CI=true` sets the `CI` environment variable inside the container.
- `-d` runs the container in detached mode.
- `--name` assigns the specified container name.
- `-p <host_port>:<app_port>` maps the host port to the application's container port.

The resulting command follows this structure:

`docker run -e CI=true -d --name <container_name> -p <host_port>:<app_port> <image>`

The subprocess uses `check=True`, so a failed Docker command raises an exception.

If the command succeeds, the method logs the container name and returns it.

**Important:** Successful container startup does not prove that the application is ready to serve requests. The separate health-check stage tests that behavior.

## 2. Testing Application Endpoints

The `test_container()` method requires a container name, host port, and at least one endpoint.

It accepts either a single endpoint string or a list of endpoints. Each endpoint is tested using an HTTP GET request to:

`http://localhost:<host_port>/<endpoint>`

Leading slashes are removed from the configured endpoint before the URL is constructed. For example, `health` and `/health` both produce `/health`.

### Default retry behavior

| Setting | Default | Meaning |
|---|---:|---|
| `expected_status` | `200` | Exact HTTP status code required for success. |
| `retries` | `10` | Maximum attempts for each endpoint. |
| `delay` | `2` seconds | Delay between unsuccessful attempts. |
| Request timeout | `5` seconds | Maximum wait for each individual HTTP request. |

The retry count and delay can be overridden when calling the method.

For each endpoint, the method:

1. Constructs the local HTTP URL.
2. Sends a GET request with a five-second timeout.
3. Compares the response status with `expected_status`.
4. Stops retrying that endpoint when the exact expected status is returned.
5. Retries unsuccessful responses or caught request exceptions until the attempt limit is reached.
6. Collects container logs and raises `RuntimeError` if the endpoint never passes.

**The status comparison is exact.** If the expected status is `200`, a response of `204` does not pass.

The method processes endpoints sequentially. Every configured endpoint must pass for `test_container()` to return `True`.

### What counts as a successful health check?

The check confirms that an HTTP request to the configured local endpoint returns the expected status code.

It does not inspect the response body or independently verify application-specific behavior, database connectivity, dependency health, or business functionality.

A health endpoint should therefore be designed to report the readiness conditions that matter for the application.

## 3. Failure Diagnostics

When an endpoint exhausts its retries, the method executes:

`docker logs <container>`

It prints the container's standard output and, if present, standard error. It then raises:

`RuntimeError("Application health check failed: <url>")`

This gives the calling CI layer a clear failure signal and provides application logs for troubleshooting.

The log-collection subprocess does not use `check=True`. Consequently, a failed `docker logs` command does not itself raise a `CalledProcessError`; the health-check failure is still raised afterward.

The method does not automatically restart the application or retry the entire container lifecycle.

## 4. Stopping and Removing Containers

Container shutdown and removal are separate operations.

### Stop

`stop_container(container)` validates the container name and executes:

`docker stop <container>`

It uses `check=True`, so a failed stop command raises an exception.

### Remove

`remove_container(container)` validates the container name and executes:

`docker rm <container>`

It also uses `check=True`.

The method does not use `docker rm -f`; it expects the container to be removable without force. The caller is responsible for invoking the lifecycle methods in the appropriate order.

## 5. Position in the CI Flow

The container health-check stage fits into the image lifecycle as follows:

1. A runtime handler builds the Docker image.
2. The orchestration layer tags and inspects the image.
3. `start_container()` launches a temporary container.
4. `test_container()` checks every configured HTTP endpoint.
5. The orchestration layer stops and removes the temporary container.
6. If the required checks pass, the pipeline can proceed to registry authentication and image publication.

The actual orchestration and cleanup behavior belongs to the calling code in `dependency_abstractor.py`. This class provides the lifecycle methods but does not implement an automatic `finally` block to guarantee cleanup.

## 6. Networking and Isolation Boundaries

The health check uses `localhost` and the configured host port. It therefore tests access through the local runner's published Docker port mapping.


## Important Distinction

`ContainerManager` verifies basic application startup and HTTP endpoint responsiveness. It is not a complete application test suite, a production monitoring system, or a Kubernetes deployment validation tool.

Its result is one gate in the CI pipeline: the image must start and satisfy the configured HTTP checks before the orchestration layer should treat it as ready for publication.
