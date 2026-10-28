# `dependency_abstractor.py` — CI Orchestration

## Purpose

`dependency_abstractor.py` coordinates the KUBAPP CI workflow, from application validation through component builds, image health checks, registry publication, and final result generation.

It connects the validation layer, runtime handlers, execution-environment preparation, image lifecycle operations, and downstream GitOps data.

## 1. Main Responsibilities

| Function or component | Responsibility |
|---|---|
| `main()` | Coordinates the overall workflow and determines its exit status. |
| `validation_gate()` | Checks the validation result and applies `STRICT_MODE`. |
| `classify_apps()` | Converts validated application records into component execution records. |
| `discover_extra_manifests()` | Identifies configured additional manifest files relevant to a runtime. |
| `build_component()` | Prepares and executes CI for one component, validates its image, checks container health, publishes the image, and returns its result. |
| `start_app_build()` | Runs component builds concurrently and collects their results. |
| `save_data()` | Writes successful component results to `gitops/state/final_ci_data.json`. |
| `is_file_okay()` | Checks whether a path identifies a readable, nonempty file. |

## 2. Overall Execution Flow

The `main()` function coordinates these stages:

1. Log the available Podman isolation capabilities.
2. Validate the discovered applications using `validate_apps()`.
3. Apply the validation gate according to `STRICT_MODE`.
4. Classify the validated applications into component execution records.
5. Prepare and execute component CI concurrently.
6. Build and tag images, inspect them, and test configured HTTP health endpoints.
7. Authenticate with Docker Hub and publish images for successful components.
8. Save successful component results to `gitops/state/final_ci_data.json`.
9. Return an exit status based on the workflow outcome and configured failure policy.

The script exits with status `0` on overall success and `1` when the workflow encounters a blocking failure.

## 3. Validation Gate and Strict Mode

The orchestrator calls `validate_apps()` and passes its result to `validation_gate()`.

The gate requires the result to be a dictionary containing `valid_apps` as a list. It rejects the result if that list is empty.

The `signal` field indicates whether validation completed successfully according to the validator.

| Condition | Behavior |
|---|---|
| Invalid result structure | Stop the workflow. |
| No valid applications | Stop the workflow. |
| `STRICT_MODE=true` and validation signal is false | Stop before component builds begin. |
| `STRICT_MODE=false` and validation signal is false, but valid applications exist | Continue with the validated applications. |
| Validation signal is true and valid applications exist | Continue. |

Disabling strict mode does not mean that invalid applications are passed directly to the build stage. The orchestrator still uses the validator's `valid_apps` list.

## 4. Component Classification

`classify_apps()` transforms each validated application into a component record containing the information needed for CI execution.

The record includes:

- Application and component directory paths.
- Runtime and primary manifest.
- Additional manifest files.
- Dockerfile and platform configuration file.
- Secret file and required security environment variables.
- Custom-script configuration.
- Standard and additional CI commands.
- Additional CI configuration, including health-check settings.

For CI commands, the orchestrator uses the application's configured `ci_commands` when it is truthy. Otherwise, it falls back to the runtime's defaults from `CI_COMMANDS` in `variables.py`.

The resulting components are grouped by their resolved application directory.

`discover_extra_manifests()` checks the configured extra manifests against `EXTRA_MANIFESTS` and includes matching files only when they exist as readable, nonempty files.

Classification prepares the execution records; it does not itself install dependencies or build images.

## 5. Building an Individual Component

`build_component()` handles the CI lifecycle for one component.

### Step 1: Validate the runtime and execution image

The function checks that the component's runtime belongs to `RUNTIME_LIST`, which is derived from `MANIFESTS` in `variables.py`.

It then looks up the corresponding execution image in `RUNTIME_IMAGES`. An unsupported runtime or missing execution image causes the component to fail.

### Step 2: Prepare the component environment

The function calls `prepare_component_environment()` from `manage_env.py`.

It passes the component directory, secret-file configuration, security environment variables, runtime, and execution image.

This prepares the environment needed by the runtime handler.

### Step 3: Select and run the runtime handler

The function calls `get_runtime_handler(runtime)` to select the handler.

It constructs the handler with the component's runtime, paths, manifests, Dockerfile, CI commands, additional configuration, and prepared environment.

It then invokes:

`handler.run_ci(use_script=..., ci_scripts=...)`

The handler is expected to execute the configured CI path and return a built image reference. If no image is returned, the component is treated as failed.

### Step 4: Tag and inspect the image

The function creates a `ValidateApp` instance and calls:

1. `tag()` to create the timestamped image reference.
2. `validate_image()` to inspect the tagged image locally.

An error at either stage prevents the component from proceeding to health checks and publication.

### Step 5: Test container health

The function reads the health-check configuration from `extra_ci_config["healthcheck"]`.

It obtains:

- `app_port`
- `host_port`
- `endpoints`
- `expected_status`, defaulting to `200` when absent

It starts a temporary container using `ContainerManager.start_container()` and checks the configured endpoints using `ContainerManager.test_container()`.

The container is stopped and then removed through nested `finally` blocks, so removal is attempted even if stopping raises an exception.

If container startup fails before `start_container()` returns, the cleanup block is not entered. The function therefore does not guarantee cleanup of a container that was created successfully by Docker but for which the start operation did not return normally.

### Step 6: Authenticate and publish

After the health checks pass and cleanup completes, the function calls:

1. `authenticate()` using `DOCKER_USER` and `DOCKER_PASS`.
2. `push()` to publish the tagged image.

Registry publication happens **after** the configured container health checks.

### Step 7: Return the component result

A successful component returns its name, a success flag, and a result record containing:

- `image`: the tagged image reference.
- `path`: the component directory relative to `PROJECT_ROOT`.
- `runtime`: the selected runtime.
- `extra_ci_data`: the component's additional CI configuration.
- `platform_file`: the configured platform file path, or `null` if absent.

The function catches exceptions, logs the failure, and returns a failure result instead of allowing ordinary component errors to propagate directly to the thread-pool collector.

## 6. Concurrent Component Execution

`start_app_build()` submits the classified components to a `ThreadPoolExecutor` with:

`MAX_WORKERS = 4`

This allows up to four component tasks to execute concurrently.

The function collects completed tasks using `as_completed()`. Successful results are recorded in the global `ALL_APPS` dictionary; failed components are reported and collected in a failure list.

The function returns `True` only when all submitted component tasks succeed. It returns `False` if there are no tasks or if one or more components fail.

### Concurrency considerations

- Each component is handled as an independent task.
- Results are collected as tasks finish, not in submission order.
- `ALL_APPS` is keyed by application name. If multiple successful tasks return the same application name, a later assignment can overwrite an earlier result.
- Container names and host ports must not conflict between concurrently running components. This script does not implement a separate reservation mechanism for them.

## 7. Failure Handling and `FAIL_MODE`

The orchestrator uses two different policies for validation and build failures.

| Setting | Purpose |
|---|---|
| `STRICT_MODE` | Determines whether incomplete validation blocks the build stage. |
| `FAIL_MODE` | Determines whether component build failures block overall workflow success. |

After component execution:

- If any component fails and `FAIL_MODE=true`, the workflow exits with status `1` without saving the final result file.
- If some components fail and `FAIL_MODE=false`, the workflow can continue to save the successful component results.
- If no component results are available to save, `save_data()` returns `False` and the workflow exits with status `1`.
- If the result file cannot be written, the workflow exits with status `1`.

Disabling `FAIL_MODE` does not turn failed components into successful ones. It allows the workflow to finish successfully when successful component results can be saved despite other component failures.

## 8. Final CI Data

`save_data()` writes the collected results to:

`gitops/state/final_ci_data.json`

The output has this structure:

```json
{
  "env": "dev",
  "apps": {
    "example_app": {
      "image": "dockeruser/example_app:latest-<timestamp>",
      "path": "docker/example_app",
      "runtime": "python",
      "extra_ci_data": {},
      "platform_file": null
    }
  },
  "timestamp": "<UTC ISO 8601 timestamp>"
}
```

This is an illustrative structure; actual application names, image references, configuration, and paths depend on the run.

The `env` field comes from the `ENV` environment variable and defaults to `dev`. The timestamp is generated using the current UTC time.

The function creates the parent directory when necessary, writes JSON to a temporary file, and replaces the target file with that temporary file after writing succeeds.

This replacement strategy helps prevent downstream consumers from reading a partially written final file.

The output contains only successful component results recorded in `ALL_APPS`. Failed components are not included.

## 9. Environment Variables and Configuration

| Setting | Default | Purpose |
|---|---|---|
| `ENV` | `dev` | Environment recorded in the final CI data. |
| `STRICT_MODE` | `true` | Blocks builds when validation does not succeed completely. |
| `FAIL_MODE` | `true` | Makes component failures block overall workflow success. |
| `DOCKER_USER` | Unset | Docker Hub username used for image tagging and authentication. |
| `DOCKER_PASS` | Unset | Docker Hub password supplied to the authentication method. |
| `MAX_WORKERS` | `4` | Maximum concurrent component tasks, defined in the script. |

The Boolean environment variables are parsed by stripping surrounding whitespace, converting to lowercase, and comparing the result with the string `true`. Other values are treated as false.

## 10. Important Boundaries

`dependency_abstractor.py` orchestrates the CI workflow but delegates specialized operations to other components:

- `validate.py` validates application configuration.
- `manage_env.py` prepares component environments and secrets.
- `detect_runtime.py` selects the runtime handler.
- Runtime handlers perform dependency preparation, configured checks, and image building.
- `command_policy.py` screens supported configured commands where its enforcement paths are used.
- `app_validator.py` handles image tagging, inspection, authentication, and publication.
- `container.py` starts test containers and checks HTTP endpoints.
- `check_podman_capability.py` reports available Podman capabilities.
- `reuse.py` provides shared utilities.

The call to `log_podman_capability_assessment()` logs the available capabilities. Its presence alone does not establish that every component command is executed inside an enforced Podman sandbox.

Likewise, concurrent execution does not itself provide isolation. Actual isolation depends on the execution mechanisms and policies used by the runtime handlers and command-execution components.

## Summary

`dependency_abstractor.py` is the coordinator for KUBAPP's CI workflow. It validates and classifies applications, executes component CI concurrently, checks built images and container health, publishes successful images, and writes results for downstream GitOps processing.

Its final exit status depends on validation policy, component outcomes, and whether successful results can be saved.
