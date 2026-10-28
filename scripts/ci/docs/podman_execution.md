# KUBAPP CI — Podman Execution Backend

## Overview

`podman_execution.py` implements the container execution backend used to run developer-controlled KUBAPP CI commands.

It constructs and launches a disposable Podman container for each command, applying configured resource limits, filesystem settings, network policy, environment variables, and dependency mounts.

The backend is designed to prevent component commands from executing directly on the host when container execution fails.

**Primary responsibilities:**
- Resolve Podman from predefined executable paths.
- Validate execution image, network policy, runtime, and dependency configuration.
- Construct Podman commands with filesystem and resource restrictions.
- Mount the component directory and prepared dependencies.
- Configure the container environment.
- Execute commands with a timeout.
- Attempt container termination and removal after execution or failure.
- Return command results or raise an execution error.

This module implements the lower-level execution mechanism used by `ComponentEnvironment`.

## Main Components

### 1. `PodmanExecutionError`

A custom exception raised when the Podman execution boundary cannot be established or the command cannot be launched or completed within the configured timeout.

Examples include:
- An invalid execution image.
- An unsupported network policy or runtime.
- Incomplete runtime dependency configuration.
- Podman missing from the supported executable paths.
- An invalid dependency directory.
- A writable path outside the component directory.
- A timeout or operating-system error while launching Podman.

A command that completes with a nonzero exit code does not directly cause this exception. Instead, `run()` returns a `CompletedProcess` containing the exit code, allowing `ComponentEnvironment` to handle the command failure.

### 2. `PodmanExecution`

The main class responsible for constructing and running a command inside a disposable container.

It receives the execution configuration from `ComponentEnvironment`, including:
- Container image.
- Component directory and environment.
- Writable paths.
- CPU, memory, and process limits.
- No-new-privileges setting.
- Docker-socket visibility setting.
- Network policy.
- Optional prepared dependency directory.
- Runtime identifier.

The constructor resolves the component and writable paths and validates the supplied runtime configuration.

If a dependency directory is supplied, it must contain the runtime-specific dependency directory and the configured required runtime file or symbolic link.

## Podman Executable Resolution

The `_podman_path()` method searches two fixed locations:

- `/usr/local/bin/podman`
- `/usr/bin/podman`

A candidate must be a regular file and executable by the current process.

If neither path qualifies, the method raises `PodmanExecutionError`.

Using fixed paths avoids resolving Podman through an arbitrary `PATH` when selecting the executable. It does not, by itself, establish that the Podman binary or the host's container runtime configuration is trusted.

## Container Configuration

The `_build_command()` method constructs the arguments passed to `podman run`.

Each command uses a unique container name generated from a UUID, prefixed with `kubapp-ci-`.

The container is launched with the following options.

| Setting | Configuration | Purpose |
|---|---|---|
| Container name | Unique `kubapp-ci-...` name | Identifies the individual execution container. |
| Cleanup | `--rm` | Requests automatic container removal when the container exits. |
| Image pulling | `--pull=never` | Prevents Podman from pulling an image as part of this invocation. |
| Root filesystem | `--read-only` | Makes the container's root filesystem read-only. |
| Temporary storage | `/tmp`, 128 MiB | Provides writable temporary storage with `nosuid` and `nodev`. |
| Home directory | `/tmp/kubapp-home`, 16 MiB | Provides a separate writable home directory with `nosuid` and `nodev`. |
| Working directory | A path beneath `/workspace` | Sets the command's working directory inside the container. |
| CPU limit | `cpu_quota_percent / 100` | Converts the configured percentage into the CPU value passed to Podman. |
| Memory limit | Configured byte count | Sets the container memory limit. |
| Memory plus swap | Equal to memory limit | Requests a combined memory-and-swap limit equal to the memory limit. |
| Process limit | Configured process count | Sets the container PID limit. |
| User | `0:0` | Runs the command as root inside the container. |
| Component mount | `/workspace`, read-write | Makes the component directory available inside the container. |

The container attaches standard output and standard error and runs interactively without receiving input from the host's standard input.

### Resource limits

The default `ExecutionPolicy` in `component_execution_env.py` specifies:
- CPU quota: 100%, passed as `--cpus 1.0`.
- Memory: 512 MiB.
- Memory plus swap: 512 MiB.
- Process limit: 64.
- Command timeout: 120 seconds.

These are defaults from the higher-level policy, not hard-coded defaults inside `PodmanExecution`. Other callers can supply different values.

The effective enforcement of these limits depends on Podman, the host's operating system, and the configured container runtime.

### Read-only root filesystem

The `--read-only` option prevents normal writes to the container's root filesystem.

The backend separately creates writable temporary filesystems for `/tmp` and the configured container home directory.

However, the component directory is mounted read-write at `/workspace`. Consequently, the component's files are writable from inside the container under the permissions and access controls in effect.

A read-only container root does not mean that the entire container filesystem is read-only.

### Privilege settings

When `no_new_privileges` is enabled, the backend adds:

`--security-opt no-new-privileges`

This requests the corresponding restriction from Podman.

When `hide_docker_socket` is enabled, the implementation adds no socket mount. The code does not otherwise inspect the container image or the host environment to prove that no other route to a container-management interface exists.

The backend also explicitly sets `--user 0:0`. Therefore, commands run as root inside the container, even when the no-new-privileges option is enabled. These are distinct settings: no-new-privileges does not make the process non-root.

## Network Policy

The constructor accepts two network policies:

- `disabled`
- `enabled`

When the policy is `disabled`, `_build_command()` adds:

`--network none`

This requests a container network configuration without normal network connectivity through Podman's network setup.

When the policy is `enabled`, the backend does not add a network restriction, leaving networking to Podman's default behavior and configuration.

The higher-level `ComponentEnvironment` emits a warning when disabled networking is requested. The actual restriction is applied here through the Podman command.

The effect of `--network none` should still be verified in the deployed environment. It does not, by itself, prove the absence of every possible host-mediated communication channel.

## Filesystem Mounts

### Component directory

The component directory is mounted at:

`/workspace`

The mount is read-write.

The command's working directory is calculated by taking its path relative to the host component directory and placing that relative path beneath `/workspace`.

For example, a host working directory corresponding to `src` becomes `/workspace/src` inside the container.

The higher-level `ComponentEnvironment` validates working-directory containment before calling this backend.

### Additional writable paths

For every configured writable path other than the component directory, the backend calculates its path relative to the component directory and mounts it read-write beneath `/workspace`.

A writable path outside the component directory causes `PodmanExecutionError`.

This provides an additional backend-level check against writable paths outside the component tree.

The implementation does not explicitly reject every possible overlapping or nested mount arrangement. The effective filesystem behavior also depends on the resolved paths and Podman's mount handling.

### Prepared dependencies

When a dependency directory is configured, it is mounted read-only at:

`/opt/kubapp-dependencies`

The mount allows component commands to access the prepared runtime environment without receiving write access through that mount.

For the Node.js runtime, the backend also mounts the configured dependency directory at:

`/workspace/node_modules`

This mount is read-only and exposes the prepared Node.js dependencies at the conventional location expected by many Node.js applications.

The runtime-specific paths are obtained from `RUNTIME_DEPENDENCY_CONFIG` in `variables.py`.

These mounts protect the mounted dependency paths from writes through those mounts. They do not independently establish that the dependencies are trustworthy or that no other writable copy exists.

## Container Environment

The backend constructs a launcher environment containing:

- `HOME`, set to the host user's home directory.
- A fixed `PATH` containing `/usr/local/bin`, `/usr/bin`, and `/bin`.
- `LANG=C.UTF-8`.

It then overlays `self.component_env` onto that mapping before invoking Podman.

This launcher environment is used by the host-side Podman process. It should not be confused with the environment received by the process running inside the container.

For the container itself, `_build_command()` explicitly configures:
- `HOME=/tmp/kubapp-home`
- `PATH`, calculated by `_container_path_value()`
- `LANG=C.UTF-8`

If a prepared dependency environment exists, the configured runtime executable directory is prepended to the container `PATH`.

The backend then adds each variable name from `component_env` as a Podman `--env` argument, excluding `HOME`, `PATH`, and `LANG`. Podman receives these variable names and obtains their values from the environment supplied to the launcher.

This allows the prepared component environment to provide variables to the container while the backend controls the three reserved variables.

## Command Execution and Timeout Handling

The `run()` method coordinates a single command execution.

Its flow is:

1. Resolve the Podman executable.
2. Generate a unique container name.
3. Construct the Podman command.
4. Construct the host-side launcher environment.
5. Execute Podman with the component directory as the host working directory.
6. Capture standard output and standard error.
7. Enforce the configured subprocess timeout.
8. Attempt container termination and removal.
9. Return a `CompletedProcess` result.

The command is passed as an argument sequence. This backend does not itself concatenate the component command into a shell command string.

### Timeout handling

If the Podman subprocess exceeds the supplied timeout, the backend attempts to terminate and remove the named container, then raises `PodmanExecutionError`.

If Podman cannot be launched because of an operating-system error, the backend performs the same cleanup attempt and raises `PodmanExecutionError`.

The timeout applies to the host-side Podman invocation. Its effectiveness in terminating the workload depends on the cleanup behavior and the container runtime.

### Container cleanup

The `_terminate_container()` method attempts two operations:

1. `podman kill <container-name>`
2. `podman rm --force <container-name>`

Each operation has a five-second timeout. Standard input and output streams are redirected to avoid producing additional cleanup output, and cleanup errors are ignored.

The cleanup helper is called in the `finally` block after the main Podman invocation, and it is also called in the timeout and operating-system error handlers.

Because the `finally` block runs after these handlers, cleanup may be attempted more than once on those failure paths.

The `--rm` option also requests automatic removal when the container exits.

**Cleanup is best-effort.** The helper suppresses cleanup failures and does not verify afterward that the container was successfully removed. It also cannot guarantee termination of unrelated processes or workloads outside the container.

## Result Handling

If Podman returns a nonzero exit code, `run()` returns a `CompletedProcess` with:
- The original component command as `args`.
- The nonzero return code.
- Captured standard output.
- Captured standard error, with an appended elapsed-time message.

If Podman returns zero, the backend returns a successful `CompletedProcess` containing the captured output.

The elapsed time is measured using `time.monotonic()`.

The backend does not convert a component command's nonzero exit code into `PodmanExecutionError`. The calling `ComponentEnvironment` is responsible for interpreting the returned status and raising `ComponentEnvironmentError` when appropriate.

## Security Boundaries and Limitations

| Area | What the backend does | Important limitation |
|---|---|---|
| Container execution | Invokes each command through Podman. | The host's Podman configuration and runtime remain part of the trust boundary. |
| Host fallback | Raises an execution error when Podman cannot be launched or the invocation times out. | Other CI code paths must also avoid bypassing this backend. |
| Image handling | Uses `--pull=never`. | This does not verify image provenance, digest pinning, or image contents. |
| Root filesystem | Requests a read-only container root. | `/workspace` is explicitly mounted read-write, and temporary filesystems are writable. |
| Process identity | Runs as `0:0` inside the container. | Container root is not equivalent to a non-root workload and must be considered in the threat model. |
| Resource limits | Passes CPU, memory, swap, and PID limits to Podman. | Effective enforcement depends on the host and runtime. |
| Network | Adds `--network none` when networking is disabled. | The actual network behavior should be tested in the deployed environment. |
| Dependencies | Mounts the prepared dependency directory read-only. | Read-only access does not verify dependency integrity or prevent all alternate access paths. |
| Docker socket | Does not add a host socket mount. | The code does not verify every possible container-management access path. |
| Cleanup | Attempts to kill and force-remove the container. | Cleanup failures are suppressed, and successful removal is not verified. |
| Secrets | Supplies configured environment variables to the container. | Secrets available in the component environment may be readable by component commands. |

The backend establishes a concrete container-execution path with several restrictions, but it should not be described as a complete security sandbox without testing and validating the effective runtime configuration.

## Relationship to Other CI Modules

| Module | Responsibility |
|---|---|
| `component_execution_env.py` | Validates component commands, working directories, environment variables, and execution policy before delegating execution. |
| `command_policy.py` | Performs command-policy checks in the CI execution flow. |
| `reuse.py` | Provides `run_component_command()` to route component-controlled commands through the execution boundary. |
| `dependency_mgt.py` | Dispatches dependency preparation to the appropriate runtime manager. |
| `python_mgt.py` | Prepares Python dependencies and performs associated checks. |
| `node_mgt.py` | Prepares Node.js dependencies and performs associated checks. |
| `run_ci.py` | Coordinates component CI execution. |

## Summary

`podman_execution.py` is the low-level backend that runs component-controlled KUBAPP CI commands in disposable Podman containers. It configures resource limits, a read-only container root, writable component mounts, optional read-only dependency mounts, network policy, environment variables, and timeout handling.

It also terminates and remove containers after execution.
Important implementation details remain part of the security assessment: commands run as container root, the component directory is mounted read-write, launcher environment variables are inherited from the prepared component environment, and cleanup is best-effort. These behaviors should be considered alongside the higher-level validation layer and verified against the actual Podman runtime.
