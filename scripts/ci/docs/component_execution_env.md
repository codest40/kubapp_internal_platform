# KUBAPP CI — Component Execution Environment

## Overview

`component_execution_env.py` defines the execution boundary for developer-controlled commands in KUBAPP's CI pipeline.

It validates command arguments, environment variables, working directories, dependency environments, and execution policies before delegating command execution to `PodmanExecution`.

The component environment is designed to prevent developer-controlled commands from falling back to direct host-subprocess execution when the Podman execution boundary fails.

**Primary responsibilities:**
- Validate component environment variables and command arguments.
- Enforce configured execution-policy constraints.
- Restrict command working directories to the component directory.
- Validate writable directories and prepared dependency environments.
- Delegate execution to the Podman backend with resource and filesystem configuration.
- Apply execution timeouts and report command failures with bounded diagnostic output.

This module provides the interface and validation layer for component-command execution. The actual container restrictions depend on the implementation of `podman_execution.py` and the capabilities of the underlying runtime.

## Main Components

### 1. `ComponentEnvironmentError`

A custom exception raised when the component environment cannot be configured or a command cannot be executed successfully.

It can carry:
- `returncode`: the failed command's exit code, when available.
- `stdout`: captured standard output.
- `stderr`: captured standard error.

Command output included in the exception message is limited to 4,000 characters per output stream. The original captured output remains available through the exception attributes.

### 2. `ExecutionPolicy`

A dataclass defining the execution restrictions supplied to the Podman backend.

Default configuration:

| Setting | Default | Purpose |
|---|---|---|
| `network` | `disabled` | Requests the backend's disabled-network policy. |
| `filesystem` | `restricted` | Requires the supported restricted-filesystem policy. |
| `no_new_privileges` | `True` | Requests the corresponding privilege restriction from the backend. |
| `hide_docker_socket` | `True` | Requests that the Docker socket be hidden. |
| `cpu_quota_percent` | `100` | Sets the configured CPU quota percentage. |
| `memory_bytes` | `536870912` | Sets a 512 MiB memory limit. |
| `process_limit` | `64` | Sets the process limit. |
| `timeout_seconds` | `120` | Sets the default command timeout in seconds. |

The `validate()` method accepts only `disabled` or `enabled` for network policy and requires `filesystem` to be `restricted`. CPU quota, memory, process limit, and timeout must be positive integers; booleans are explicitly rejected for these numeric settings.

Although `filesystem` is validated, this module does not pass that setting directly to `PodmanExecution`. The backend must implement the actual filesystem restrictions.

### 3. `ComponentEnvironment`

The main class responsible for preparing and managing the execution environment for a component.

Its constructor requires:
- `app_name`: a nonempty component/application name.
- `component_dir`: an existing component directory.
- `component_env`: an explicitly prepared mapping of environment-variable names to string values.
- `runtime`: a supported runtime present in `RUNTIME_DEPENDENCY_CONFIG`.
- `execution_image`: a nonempty container image name.

Optional parameters include:
- `writable_paths`: directories the backend may configure as writable.
- `policy`: a custom `ExecutionPolicy`.
- `dependency_dir`: a prepared runtime dependency directory.

The component directory is resolved to an absolute path. If `writable_paths` is omitted, the component directory is the default writable path. If supplied explicitly, the list must still include the component directory.

The class also tracks `last_execution_mode`, allowing callers to distinguish successful Podman execution from a Podman execution failure.

## Environment Variable Validation

The `_validate_environment()` method validates the supplied component environment before execution.

It enforces the following rules:

- Variable names must match the pattern `^[A-Za-z_][A-Za-z0-9_]*$`.
- Values must be strings.
- Values cannot contain NUL bytes.
- Each value is limited to 32,768 characters.

The method copies accepted entries into a new dictionary rather than retaining the original mapping directly.

These checks validate the shape and size of environment data. They do not determine whether a variable contains a secret or whether the value is appropriate to expose to a component command.

## Writable Directory Validation

The `_validate_writable_paths()` method resolves each supplied path and requires it to be an existing directory.

It rejects:
- Paths that cannot be resolved.
- Paths that are not directories.
- The filesystem root (`/`).
- Configurations that omit the component directory from the writable-path list.

Duplicate resolved paths are removed while preserving their original order.

These are host-side path-validation checks. The actual read/write permissions available inside the execution container depend on how `PodmanExecution` mounts and configures those paths.

## Working Directory and Command Validation

### Command arguments

The `_validate_command()` method requires commands to be provided as a sequence of arguments, rather than a single string or bytes object.

Each argument must:
- Be a string.
- Be nonempty.
- Contain no NUL byte.

The resulting argument list is passed to the backend. This interface does not itself invoke a shell or prove that the executable or its arguments are safe; command policy checks are handled elsewhere in KUBAPP's CI flow.

### Working directory

The `_resolve_working_directory()` method resolves the requested working directory, or defaults to the component directory.

It requires the resolved path to:
- Exist.
- Be a directory.
- Remain within the resolved component directory.

A working directory outside the component directory is rejected.

This is a path-containment check for the selected working directory. It should not be interpreted as a guarantee that every file accessible to a process is confined to the component directory; the backend's mount and filesystem configuration determines the process's actual filesystem access.

### Timeout

The `_resolve_timeout()` method uses the policy's default timeout unless a per-command timeout is supplied.

The resolved timeout must be a positive integer, with booleans rejected.

The timeout is passed to `PodmanExecution.run()`. The backend is responsible for enforcing it during command execution.

## Prepared Dependency Environment

The `set_dependency_environment()` method attaches an existing prepared dependency directory for use by component commands.

It validates that:
1. The directory can be resolved and exists.
2. The runtime has a dictionary configuration in `RUNTIME_DEPENDENCY_CONFIG`.
3. The configured runtime dependency directory exists beneath the supplied dependency directory.
4. The configured required runtime path is either a file or a symbolic link.

The method then stores the resolved directory in `self.dependency_dir`.

The runtime-specific paths are supplied by `variables.py`, allowing Python and Node.js dependency environments to use their respective layouts.

**Important:** These checks verify the existence of expected paths. They do not independently establish the integrity, safety, or correctness of installed dependencies. The backend is responsible for making the prepared dependency environment available with the intended permissions.

## Launcher Environment

The `_launcher_environment()` helper constructs a minimal environment containing:
- `HOME`
- A fixed `PATH`
- `LANG=C.UTF-8`
- `XDG_RUNTIME_DIR`, when present in the host environment
- `DBUS_SESSION_BUS_ADDRESS`, when present in the host environment

This helper is not called by `run()` in the supplied implementation. Therefore, its existence alone does not establish which environment variables the Podman launcher actually receives. That behavior depends on the backend and its subprocess configuration.

## Component Command Execution

The `run()` method coordinates command execution.

Its execution flow is:

1. Validate the command arguments.
2. Resolve and validate the working directory.
3. Resolve the command timeout.
4. Determine the command label for diagnostics.
5. Confirm that an execution image is configured.
6. Emit a warning when the network policy is `disabled`.
7. Create a `PodmanExecution` instance with the component's configuration.
8. Invoke the backend's `run()` method with the command, working directory, and timeout.
9. Record the execution mode as `podman` on success.
10. Inspect the returned exit code and raise `ComponentEnvironmentError` if the command failed.

The backend receives:
- The execution image.
- The component directory.
- The validated component environment.
- The writable-path list.
- CPU quota, memory, and process limits.
- The no-new-privileges and Docker-socket settings.
- The configured network policy.
- The prepared dependency directory.
- The runtime identifier.

### Failure handling

If the backend raises `PodmanExecutionError`, the environment records `last_execution_mode` as `podman_failed` and raises `ComponentEnvironmentError`.

There is no fallback to executing the component command directly through a host subprocess.

If the backend returns a nonzero exit code, the environment raises `ComponentEnvironmentError` containing the exit code, elapsed time, and bounded diagnostic output. The original standard output and standard error are also attached to the exception.

A successful command returns the backend's `CompletedProcess` result.

## Network Policy Warning

When the configured network policy is `disabled`, `run()` calls `_report_degraded_execution()`.

The warning states that the disabled-network policy is implemented by the backend and cautions against assuming OS-level isolation where a restriction has not been demonstrated.

The warning is emitted through Python's warning mechanism and printed to standard output.

**This warning does not itself disable networking or verify that networking is disabled.** The actual behavior must be confirmed in `podman_execution.py` and tested against the configured Podman runtime.

## Security Boundaries and Limitations

The component execution environment provides several useful validation and execution controls, but its guarantees depend on the backend and surrounding CI flow.

| Control | What this module establishes | What still requires verification |
|---|---|---|
| Command input | Rejects malformed command sequences and arguments. | Whether the selected command is permitted by KUBAPP's command policy. |
| Working directory | Requires the resolved working directory to remain inside the component directory. | The complete filesystem view available to the running process. |
| Environment variables | Validates names, value types, NUL bytes, and value lengths. | Whether supplied values expose credentials or other sensitive data. |
| Resource policy | Validates positive CPU, memory, process, and timeout values. | Whether the backend and host enforce the requested limits as intended. |
| Filesystem policy | Accepts only the supported `restricted` policy value. | The actual mounts, write permissions, and filesystem isolation. |
| Network policy | Accepts `disabled` or `enabled` and warns when disabled mode is requested. | Whether network access is actually disabled or otherwise restricted. |
| Privilege controls | Passes the no-new-privileges and Docker-socket settings to the backend. | Whether the backend correctly implements these controls. |
| Execution failure | Converts backend errors and nonzero exit codes into component-environment exceptions. | Whether upstream callers handle these exceptions safely and consistently. |
| Dependency environment | Checks for expected runtime paths before attaching the directory. | Dependency integrity and the effective permissions used at runtime. |
| Host fallback | Does not execute the component command directly when Podman execution fails. | Whether other CI code paths bypass this execution boundary. |

The absence of host-subprocess fallback is an important fail-closed behavior for component commands. However, it does not by itself establish that the container is fully isolated or that every developer-controlled operation in the pipeline passes through this class.

## Relationship to Other CI Modules

| Module | Responsibility |
|---|---|
| `reuse.py` | Provides `run_component_command()` as the shared interface for component-controlled commands. |
| `command_policy.py` | Performs command-policy checks before commands are dispatched through the relevant CI execution flow. |
| `podman_execution.py` | Implements the lower-level Podman execution behavior and must enforce the requested runtime restrictions. |
| `dependency_mgt.py` | Dispatches dependency staging to the appropriate runtime manager. |
| `python_mgt.py` | Prepares Python dependencies and performs associated checks. |
| `node_mgt.py` | Prepares Node.js dependencies and performs associated checks. |
| `run_ci.py` | Coordinates CI execution and invokes component commands through the shared execution interface. |

## Summary

`component_execution_env.py` is KUBAPP's component-command execution boundary. It validates inputs, constrains working-directory selection, checks prepared dependency layouts, passes resource and isolation settings to the Podman backend, and refuses to fall back to direct host execution when that backend fails.

Its guarantees must be assessed together with `podman_execution.py`, the command-policy layer, and the callers that route developer-controlled commands into this environment. Configuration validation and container invocation are important controls, but neither alone proves that all intended isolation restrictions are enforced.
