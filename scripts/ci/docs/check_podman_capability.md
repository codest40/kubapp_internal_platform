# KUBAPP CI — Podman Capability Assessment

## Overview

`check_podman_capability.py` assesses whether the Podman environment can demonstrate the container restrictions expected by KUBAPP's CI execution boundary.

It checks Podman availability and evaluates selected runtime controls using disposable diagnostic containers. Each assessment produces a status and an explanation of what was or was not demonstrated.

**Primary responsibilities:**
- Check Podman availability and runtime information.
- Determine whether Podman reports rootless operation.
- Assess user namespace separation.
- Verify selected privilege, filesystem, network, and resource controls.
- Check whether standard Docker socket paths are exposed inside a diagnostic container.
- Report results using structured capability statuses.
- Log assessment results without making CI execution-policy decisions.

This module is diagnostic. It does not configure the production execution environment, automatically repair unsupported controls, or block CI execution based on the report.

## Main Components

### 1. `SandboxBackendError`

A custom exception used when a diagnostic command cannot be executed correctly.

It covers conditions such as:
- Podman being unavailable.
- A diagnostic command timing out.
- The operating system being unable to launch a diagnostic command.
- A container-level probe being attempted before the diagnostic image is available.

Individual probes may convert these failures into warning results rather than allowing the entire assessment to fail.

### 2. `AssessmentStatus`

An enumeration defining the possible outcomes of an individual capability assessment.

| Status | Meaning |
|---|---|
| `PASS` | The control was demonstrated by the check. |
| `WARNING` | The check did not demonstrate the expected control, or the result indicates a potential limitation. |
| `BLOCK` | Reserved for an explicit policy decision. The current diagnostic does not make such decisions. |
| `NOT_ASSESSED` | The check could not be run or its result could not be verified. |

A `PASS` means the specific probe succeeded. It does not prove that the complete CI execution environment is secure.

A `WARNING` is not necessarily proof that a control is absent. It may indicate that the check could not demonstrate the control.

### 3. `CapabilityResult`

A dataclass representing one capability assessment.

Each result contains:
- `name`: the capability being assessed.
- `status`: the assessment status.
- `detail`: a human-readable explanation.

The `supported` property returns `True` only when the status is `PASS`.

### 4. `BackendReport`

A dataclass containing the complete collection of capability results.

It provides several summary properties:

- `blocked`: returns `True` if any result has status `BLOCK`.
- `has_warnings`: returns `True` if any result has status `WARNING`.
- `not_assessed`: returns the results marked `NOT_ASSESSED`.
- `supported`: returns `True` only if at least one capability was assessed and every reported capability passed.
- `unsupported`: returns the results marked `WARNING`.

The `summary()` method formats the results into a readable report and calculates an overall status.

Possible overall messages include:

- `BLOCKED BY EXPLICIT POLICY`
- `DEGRADED - WARNINGS OR UNASSESSED CONTROLS`
- `ALL ASSESSED CONTROLS PASSED`
- `NO CAPABILITIES ASSESSED`

The `unsupported` property contains warning results only; it does not include `NOT_ASSESSED` results.

## Backend Initialization

### `PodmanSandboxBackend`

The main class responsible for running the diagnostic checks.

Its constructor accepts:

| Parameter | Default | Purpose |
|---|---|---|
| `podman` | Automatically discovered | Optional Podman executable path. |
| `probe_image` | `docker.io/library/alpine:3.22`, unless overridden | Image used for container-level probes. |
| `probe_timeout_seconds` | `10` | Default timeout for diagnostic commands. |
| `image_pull_timeout_seconds` | `30` | Timeout for obtaining the diagnostic image. |

The probe image can also be configured through the `KUBAPP_PODMAN_PROBE_IMAGE` environment variable.

If a Podman path is not explicitly provided, the constructor uses `shutil.which("podman")`. This differs from `podman_execution.py`, which searches fixed executable paths.

Both timeout values must be positive integers; booleans are rejected.

The backend initially marks the diagnostic image as unavailable. Container-level probes are permitted only after the image has been confirmed available or successfully pulled.

## Assessment Workflow

The `assess()` method coordinates the capability checks.

### Step 1: Check Podman availability

If Podman cannot be found on `PATH`, the report marks availability as `WARNING` and the remaining controls as `NOT_ASSESSED`.

If Podman is found, the backend runs:
- `podman --version`
- `podman info --format json`

If either command fails, the method returns an availability warning report.

When the initial runtime checks fail, the implementation does not continue with the remaining capability probes.

### Step 2: Assess rootless execution

The backend reads Podman's JSON runtime information and examines:

`host.security.rootless`

The result is interpreted as follows:

- `true`: `PASS`
- `false`: `WARNING`
- Missing or unparseable status: `NOT_ASSESSED`

This reports what Podman says about its operating mode. It does not independently prove that every container has the intended user-namespace or privilege restrictions.

### Step 3: Prepare the diagnostic image

The `_prepare_image()` method checks whether the configured diagnostic image already exists locally.

If it exists, the image is marked ready.

Otherwise, the backend attempts to pull it within the configured image-pull timeout.

If the pull fails, the result is `NOT_ASSESSED`, and the container-level probes are skipped.

The failure details are taken from the pull command's standard error or standard output, with the displayed detail limited to the last 500 characters.

The image is used for diagnostics; this code does not verify its provenance, pin it to a digest, or establish that its contents are trusted.

### Step 4: Run container-level probes

When the diagnostic image is ready, the backend runs individual checks for:
- User namespace separation.
- No-new-privileges.
- Read-only root filesystem.
- Network namespace isolation.
- CPU quota.
- Memory limit.
- Process limit.
- Standard Docker socket exposure.

Each probe returns a `CapabilityResult`.

If a probe raises one of the handled backend, operating-system, or subprocess exceptions, the assessment records a `WARNING` for that capability and continues with the remaining checks.

## Individual Capability Checks

### 1. User Namespace Separation

The `_probe_user_namespace()` method compares the host's user namespace identifier with the identifier reported inside a diagnostic container.

The host identifier is obtained from `/proc/self/ns/user`. The container identifier is obtained by running `readlink /proc/self/ns/user` inside the container.

A different identifier results in `PASS`, while matching identifiers result in `WARNING`.

If either identifier cannot be read or the container probe fails, the result is a warning or `NOT_ASSESSED`, depending on the failure.

This check demonstrates namespace separation for the diagnostic process. It does not measure every aspect of user-namespace mapping or prove that container-root privileges are harmless.

### 2. No-New-Privileges

The `_probe_no_new_privileges()` method starts a container with:

`--security-opt=no-new-privileges`

It then checks `/proc/self/status` for:

`NoNewPrivs: 1`

If the expected value is found, the check passes. Otherwise, it produces a warning.

This demonstrates the reported state of the diagnostic process under the requested option. It does not verify every privilege-related restriction in the production command-execution configuration.

### 3. Read-Only Root Filesystem

The `_probe_read_only_rootfs()` method starts a diagnostic container with:

`--read-only`

Inside the container, it attempts to create a file under `/etc`.

The probe passes when the write attempt is denied and the diagnostic command returns success.

If the command returns a nonzero status, the result is a warning.

This tests a write to one location under the diagnostic configuration. It does not inspect every mount or establish that writable component directories and temporary filesystems are configured correctly in production.

### 4. Network Namespace Isolation

The `_probe_network_isolation()` method obtains the host's network namespace identifier, then runs a diagnostic container with:

`--network=none`

It reads the container's network namespace identifier and compares it with the host identifier.

A different, nonempty identifier results in `PASS`. Otherwise, the result is `WARNING`.

This check demonstrates a separate network namespace under the diagnostic configuration. It does not directly test outbound connectivity or prove that all host-mediated communication paths are unavailable.

### 5. CPU Limit

The `_probe_cpu_limit()` method runs a container with:

`--cpus=0.5`

It reads `/sys/fs/cgroup/cpu.max` and parses the quota and period values.

The check passes when both values are positive and the quota-to-period ratio is no greater than `0.5`.

If the cgroup value cannot be read or parsed, or the expected quota is not demonstrated, the result is a warning.

This tests a diagnostic limit of half a CPU. It does not verify the production policy's configured CPU value.

### 6. Memory Limit

The `_probe_memory_limit()` method runs a container with:

- `--memory=128m`
- `--memory-swap=128m`

It reads `/sys/fs/cgroup/memory.max` and checks whether the reported value is a positive integer no greater than 128 MiB.

A matching finite limit results in `PASS`; otherwise, the check produces a warning.

The probe tests a 128 MiB diagnostic limit, not the 512 MiB default configured by `ExecutionPolicy`.

### 7. Process Limit

The `_probe_process_limit()` method runs a container with:

`--pids-limit=64`

It reads `/sys/fs/cgroup/pids.max` and checks whether the reported value is a positive integer no greater than 64.

The value `max` is treated as evidence that no finite limit was demonstrated and results in a warning.

This checks whether the diagnostic container reports a finite PID limit. It does not verify every process-related restriction in the production environment.

### 8. Docker Socket Isolation

The `_probe_docker_socket_isolation()` method checks two standard socket paths inside the diagnostic container:

- `/var/run/docker.sock`
- `/run/docker.sock`

If neither path exists as a socket, the probe passes.

If a socket is found or the check otherwise fails, the result is a warning.

The result is deliberately narrow: the check does not inspect arbitrary socket paths, other container-management interfaces, or every possible route to the host's container runtime.

## Diagnostic Command Execution

### `_run()`

The `_run()` helper executes trusted Podman diagnostic commands using `subprocess.run()`.

It:
- Passes arguments as a list.
- Captures standard output and standard error.
- Uses text mode.
- Does not automatically raise an exception for nonzero exit codes.
- Applies the requested timeout or the default probe timeout.
- Converts timeouts and operating-system launch failures into `SandboxBackendError`.

The helper is used for Podman commands such as image inspection, image pulling, runtime information retrieval, and container startup.

### `_run_container_probe()`

This helper executes a fixed diagnostic command inside a disposable container.

It requires the diagnostic image to be marked ready and builds a command using:
- `podman run`
- `--rm`
- `--pull=never`
- Any probe-specific options
- The configured diagnostic image
- The diagnostic command and its arguments

Using `--pull=never` ensures that the individual probe does not initiate a separate image pull. Image preparation is handled beforehand.

## Reporting and CI Behavior

### `log_podman_capability_assessment()`

This function is the module's reporting entry point.

It:
1. Prints a KUBAPP capability-assessment heading.
2. Creates a `PodmanSandboxBackend`.
3. Runs the assessment.
4. Prints the report summary.
5. Prints an informational message if warnings or unassessed controls exist.
6. Prints a message stating that CI will continue.
7. Catches unexpected exceptions and prints a warning.
8. Prints a closing separator.

**The function does not block CI execution.** Even when the report contains warnings or some controls could not be assessed, this function does not raise a policy-blocking error or return a decision that prevents CI from proceeding.

The implementation explicitly reserves `BLOCK` for external policy decisions and does not assign that status to its own probe results.

The reporting function's message says CI will proceed regardless of assessment problems. Whether CI actually proceeds depends on the surrounding caller and workflow.

## Security Boundaries and Limitations

| Area | What is assessed | What is not established |
|---|---|---|
| Podman availability | Executable discovery, version command, and runtime information. | That the installed binary and runtime configuration are trustworthy. |
| Rootless operation | Podman's reported rootless status. | Complete isolation or correct user mappings. |
| User namespace | Whether host and container namespace identifiers differ. | Every aspect of user-namespace security. |
| No-new-privileges | The diagnostic process's reported `NoNewPrivs` value. | Every privilege restriction in the production execution path. |
| Filesystem | Whether a test write under `/etc` is denied. | Correct restrictions on all production mounts. |
| Networking | Whether the diagnostic container has a different network namespace under `--network=none`. | Absence of all possible communication paths. |
| CPU | Whether a diagnostic CPU quota is visible in cgroups. | Enforcement of the production CPU configuration. |
| Memory | Whether a diagnostic memory limit is visible in cgroups. | Enforcement of the production memory configuration. |
| Processes | Whether a finite diagnostic PID limit is visible in cgroups. | Enforcement of every production process restriction. |
| Docker socket | Whether two standard socket paths are exposed as sockets. | Isolation from other socket paths or container-management interfaces. |
| CI decisions | Produces diagnostic results and logs. | Automatic enforcement of a fail-closed policy. |

A successful report means the assessed probes passed under their diagnostic configurations. It is not proof that every production execution control is active or that the complete CI boundary is secure.

## Relationship to Other CI Modules

| Module | Responsibility |
|---|---|
| `component_execution_env.py` | Validates component execution settings and delegates commands to the execution backend. |
| `podman_execution.py` | Constructs and runs the actual component-command containers. |
| `command_policy.py` | Checks component commands against configured command policies. |
| `reuse.py` | Provides shared utilities and component-command dispatch. |
| `run_ci.py` | Coordinates CI execution and its configured checks. |

The capability assessment is separate from the actual component execution path. It tests selected controls using a diagnostic image and its own container options rather than inspecting every setting applied to each production command.

## Summary

`check_podman_capability.py` is KUBAPP's diagnostic tool for assessing whether selected Podman execution controls can be demonstrated.

It checks runtime availability, rootless operation, namespace separation, no-new-privileges, filesystem restrictions, networking, resource limits, and standard Docker socket exposure.
Its results distinguish passed checks from warnings and controls that could not be assessed. The module reports findings but does not enforce execution policy or block CI. Its findings is diagnostic evidence, not as a guarantee that the production container execution boundary is fully isolated.
