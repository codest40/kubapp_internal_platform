# KUBAPP CI — Python Runtime and Dependency Management

## 1. Overview

KUBAPP's Python runtime implementation is split between two modules:

- **`python_handler.py`** — Integrates Python applications with the CI runner, including dependency preparation, linting, security analysis, unit tests, and optional Docker image builds.
- **`python_mgt.py`** — Creates an isolated dependency-staging environment using Podman, installs Python dependencies, audits installed packages, checks dependency consistency, generates a software bill of materials (SBOM), and publishes the SBOM to GitOps state.

The shared `dependency_mgt.py` module dispatches dependency staging to the appropriate runtime-specific manager.

The intended flow is:

1. KUBAPP discovers and validates the Python component.
2. `PythonHandler` checks that the configured Python manifest and execution image are supported.
3. KUBAPP analyzes the manifest and evaluates the result through `KUBAPP_DECISION`.
4. `stage_dependency()` dispatches the request to `stage_python_dependency()`.
5. `python_mgt.py` prepares the dependency environment inside a Podman container.
6. The installed dependencies are audited and an SBOM is generated.
7. The staged environment is registered with the component execution environment.
8. The CI runner executes the configured checks.
9. If a Dockerfile is configured, the handler can build and inspect a Docker image.

These modules coordinate the process, but their safety guarantees depend on the execution environment, command policy, container runtime configuration, and the behavior of the commands being executed.

## 2. Supported Python Dependency Manifests

The implementation supports two manifest types:

| Manifest | Dependency installation method |
|---|---|
| `requirements.txt` | Installs packages using `pip install -r`. |
| `pyproject.toml` | Copies the component source into a temporary build directory and installs the resulting Python project using `pip install`. |

The manifest must exist and resolve to a file inside the component directory.

The dependency manager rejects unsupported manifest names and manifests outside the component directory.

A valid manifest is not sufficient on its own: dependency staging also requires a configured execution image.

## 3. PythonHandler

`PythonHandler` connects the Python runtime to KUBAPP's CI orchestration.

### 3.1 Initialization

The handler receives configuration including:

- Application name and component directory.
- Parent directory and runtime.
- Primary and additional manifests.
- Optional Dockerfile.
- CI commands and extra CI commands.
- Extra CI configuration and security environment settings.
- Component execution environment.
- Optional environment variables.

When a component execution environment is provided, the handler obtains its execution image and copies its component environment variables.

Without a component execution environment, the handler can retain an environment supplied directly to the constructor. However, dependency installation subsequently requires a component execution environment to register the staged dependencies.

### 3.2 Dependency Installation

`install_dependencies()` prepares the Python dependency environment before the runner proceeds with the remaining CI stages.

The method:

1. Confirms that the primary manifest is `requirements.txt` or `pyproject.toml`.
2. Confirms that a Python execution image is configured.
3. Reads the manifest using `collect_content()`, restricting the read to the component directory.
4. Sends the manifest content to `analyze_data()` with the artifact type `module`.
5. Passes the analysis result to `KUBAPP_DECISION()`.
6. Calls `stage_dependency()` with the Python runtime, application name, component directory, manifest, and execution image.
7. Registers the resulting dependency directory through `component_environment.set_dependency_environment()`.
8. Logs the location of the prepared environment.

The analysis and decision calls happen before dependency staging. The exact enforcement performed by these calls depends on their implementations.

If dependency preparation fails, the exception propagates to the caller unless handled at a higher level.

### 3.3 Linting

`lint()` retrieves the configured `lint` command from `ci_commands`.

It then:

1. Rejects a missing or empty command.
2. Validates the command using `ensure_command_is_safe(command, "python")`.
3. Executes the command through `run_component_command()`.
4. Uses the component directory as the working directory.

The method logs success only after the command completes successfully.

### 3.4 Security Analysis

`security_analysis()` follows the same command-execution pattern as linting but retrieves the `security` command.

The command is checked against the Python command policy before execution through the component execution boundary.

The handler itself does not implement a security scanner. The actual security checks depend on the configured command and the tool it invokes.

### 3.5 Unit Tests

`unit_tests()` retrieves the configured `test` command, validates it against the Python command policy, and executes it through `run_component_command()`.

A missing command or failed execution prevents the method from reporting success.

### 3.6 Docker Image Build

`build_from_dockerfile()` handles the optional Docker image build stage.

If no Dockerfile is configured, the method logs that the build is being skipped and returns `None`.

Otherwise, it:

1. Reads the Dockerfile using `collect_content()`, restricting access to the component directory.
2. Passes the Dockerfile content to `analyze_data()` with the artifact type `dockerfile`.
3. Evaluates the analysis result through `KUBAPP_DECISION()`.
4. Obtains a commit identifier through `get_latest_commit_id()`.
5. Constructs an image tag in the form `<app_name>:<commit_id>`.
6. Executes `docker build` through `run_platform_command()`.
7. Inspects the resulting image using `docker image inspect`.
8. Returns the image name after successful completion.

The Docker build is a platform operation, so it uses `run_platform_command()` rather than the component-command execution helper.

**Important distinction:** The dependency-staging container and this Docker image build are separate operations. The staging container's resource and filesystem restrictions do not automatically apply to the later Docker build.

### 3.7 CI Runner Integration

`run_ci()` constructs a `CIRunner` with the handler, `use_script` setting, and optional CI script list. It then delegates execution to `runner.run()`.

The runner controls the order of dependency installation, configured CI checks or scripts, extra checks, and the final Dockerfile build stage.

See `run_ci.md` for the shared runner's execution flow.

## 4. Python Dependency Staging

The `python_mgt.py` module provides the dependency preparation implementation.

### 4.1 Entry Point

The main entry point is:

`stage_python_dependency(...)`

It accepts:

- `app_name`
- `component_dir`
- `manifest`
- `execution_image`
- Optional `staging_root`

It returns the path to the successfully prepared staging directory.

The function validates the application name, resolves the component and manifest paths, verifies the manifest file and component directory, checks that the manifest is supported and contained within the component directory, and validates the execution image value.

The default staging root is:

`<system temporary directory>/kubapp-ci-dependencies`

Each preparation attempt creates a unique directory under that root.

### 4.2 Podman Discovery

`_podman_path()` searches these locations:

- `/usr/local/bin/podman`
- `/usr/bin/podman`

The selected path must refer to a file with at least one executable permission bit.

If neither location qualifies, the dependency manager raises `PythonStagingError`.

This is a fixed-path lookup rather than a general search through the system's `PATH`.

### 4.3 Execution Image Availability

Before staging dependencies, `_ensure_image_available()` checks whether the configured execution image exists locally.

If the image check returns a nonzero status, the manager attempts to pull the image.

The pull operation uses the shared Podman command wrapper, which raises `PythonStagingError` if the command fails.

Because any nonzero image-existence result triggers a pull attempt, the code does not distinguish a missing image from every other possible reason for the check to fail.

### 4.4 Staging Container Configuration

Dependency installation and auditing run inside a Podman container created from the configured execution image.

The container is started with these principal restrictions:

| Setting | Configuration | Purpose |
|---|---|---|
| Container lifecycle | `--rm` | Removes the container after it exits. |
| Image pulling | `--pull=never` | Prevents the run command from pulling the image again. |
| Root filesystem | `--read-only` | Makes the container's root filesystem read-only. |
| Privilege escalation | `--security-opt no-new-privileges` | Prevents gaining additional privileges through supported privilege-escalation mechanisms. |
| CPU | `--cpus 1` | Limits CPU allocation to one CPU. |
| Memory | `--memory 1g` | Sets a 1 GiB memory limit. |
| Memory plus swap | `--memory-swap 1g` | Sets the combined memory-and-swap limit to 1 GiB where enforced by the runtime and host. |
| Processes | `--pids-limit 128` | Limits the number of processes or tasks where enforced. |
| Temporary filesystem | `/tmp` tmpfs, 256 MiB | Provides a bounded temporary filesystem with `nosuid` and `nodev`. |
| Working directory | `/workspace` | Sets the component's working directory. |
| Component source | Mounted read-only at `/workspace` | Allows reading the component without granting this container write access to that mount. |
| Dependency staging | Mounted read-write at `/opt/kubapp-dependencies` | Stores the prepared environment and SBOM. |
| Package cache | Disabled through environment settings | Avoids using the configured pip cache. |

The container runs a generated shell script using `/bin/sh -c`.

**Network access is not explicitly disabled.** Installing packages and pulling images may require network access. The configuration does not use `--network=none`.

These restrictions are useful containment measures, but their effectiveness depends on Podman, the host kernel, runtime configuration, and the surrounding host environment. They do not by themselves prove complete isolation.

## 5. Installation and Audit Sequence

The generated installation script uses `set -eu` and executes the following main operations.

### 5.1 Create the Application Virtual Environment

The application environment is created at:

`/opt/kubapp-dependencies/venv`

The script upgrades pip in that environment.

For `requirements.txt`, it installs dependencies from the supplied requirements file.

For `pyproject.toml`, it copies the component source into `/tmp/kubapp-build` and installs the copied project.

The original component directory is mounted read-only. The temporary build copy allows the installation process to work with a writable copy of the source.

### 5.2 Prepare the Audit Environment

A separate virtual environment is created at:

`/tmp/kubapp-pip-audit-venv`

The script installs the pinned audit-tool version:

`pip-audit==2.10.1`

Keeping the audit tool in a separate environment helps distinguish scanner dependencies from the application's installed dependencies.

The pin fixes the requested tool version; it does not independently guarantee that the scanner or its dependencies are free of vulnerabilities.

### 5.3 Audit Installed Dependencies

The script runs `pip-audit` against the application environment's `site-packages` directory using the tool's `--path` option.

It then runs `pip check` to check for broken or incompatible installed dependency requirements.

The sequence matters: because the script uses `set -eu` and chains its commands with `&&`, a failed installation or audit step prevents subsequent successful completion of the staging script.

The dependency audit is performed against the installed environment. It should not be described as a complete source-code security scan or as proof that the application is vulnerability-free.

### 5.4 Generate the SBOM

The script generates an SBOM at:

`/opt/kubapp-dependencies/sbom.json`

The JSON records application information and package inventories. Package names are normalized by lowercasing them and replacing runs of `-`, `_`, and `.` with `-`. The inventories are sorted, and duplicate normalized package names are detected.

The SBOM separates two package inventories:

- The application environment's installed distributions, recorded under the application's package section.
- The audit environment's installed distributions, recorded under `kubapp_data.section.packages`.

The installed `pip-audit` version is recorded in `kubapp_data.section.tools`.

This distinction is important: the scanner's dependencies are not the same inventory as the application's dependencies.

## 6. SBOM Publication

After the staging container exits successfully, `_publish_sbom()` validates the generated SBOM before publishing it.

The validation checks include:

- The application name follows the expected character pattern.
- The SBOM is a JSON object.
- The application section exists and matches the requested application name.
- The runtime is `python`.
- The expected application package section exists.
- The KUBAPP metadata section and its tool and package records have the expected structure.
- A `pip-audit` version is recorded.

The destination is:

`gitops/state/sbom/<app_name>.json`

The path is resolved relative to the repository structure determined from the module's location.

Publication uses a temporary file in the destination directory, writes formatted JSON, flushes and synchronizes the file, and atomically replaces the destination with `os.replace()`.

This reduces the risk of readers observing a partially written SBOM. It does not, on its own, provide concurrent-writer coordination or guarantee that the published SBOM corresponds to the latest successful CI run.

If publication fails, the function raises `PythonStagingError`.

## 7. Staging Metadata and Environment Registration

After publishing the SBOM, the dependency manager checks that the staged virtual-environment interpreter exists or is a symbolic link.

It then writes `.kubapp-staging-info` into the staging directory. The metadata records:

- The execution image.
- The manifest path.
- The staged virtual-environment path.
- The pinned `pip-audit` version.
- `dependency_audit=passed`.
- `installation_location=prepared_container`.

The manager returns the staging directory to `PythonHandler`, which registers it with the component execution environment.

The metadata is a record of the staging process; it should not be treated as independently verified proof of every security property of the resulting environment.

One ordering detail is important: SBOM publication occurs before the staged interpreter check. If that later check fails, the staging directory is removed, but the already published SBOM may remain.

## 8. Error Handling and Cleanup

The dependency manager uses `PythonStagingError` to report staging-specific failures.

The Podman wrapper captures standard output and standard error, checks the command's exit status, and includes failure output in the raised exception.

If an exception occurs during `stage_python_dependency()`, the staging directory is removed with `shutil.rmtree()` before the exception is re-raised.

This cleanup applies to the staging directory. It does not automatically roll back an SBOM that was published before a later failure.

The handler and runner generally allow failures to propagate, leaving higher-level CI orchestration responsible for interpreting the failure and determining the overall result.

## 9. Security Boundaries and Limitations

The implementation establishes several useful controls, but they should be understood within their actual scope.

### Controls implemented

- Python dependency manifests are restricted to supported filenames.
- Resolved manifest paths must remain inside the component directory.
- Manifest and Dockerfile contents are read through a helper that can enforce a component-root boundary.
- Manifest and Dockerfile content are passed through the AI analysis and decision flow.
- Configured lint, security, and test commands are checked against the Python command policy.
- Component commands use the component execution boundary.
- Dependency installation and auditing occur inside a Podman container with resource limits, a read-only root filesystem, and a read-only component-source mount.
- Dependency audit and package-consistency checks must succeed for the staging script to complete.
- SBOM publication validates expected metadata and uses atomic replacement.

### Important limitations

- The dependency-staging container does not explicitly disable network access.
- A read-only source mount does not prevent code from executing inside the container.
- Container restrictions depend on host and runtime enforcement.
- The command policy is not a complete sandbox or a general allowlist.
- The AI decision flow's guarantees depend on the implementations of `analyze_data()` and `KUBAPP_DECISION()`.
- The configured CI commands determine which linting, security, and testing tools actually run.
- The optional Docker build runs as a separate platform operation and is not automatically confined by the staging container's limits.
- The SBOM and staging metadata describe the preparation process; they do not establish complete provenance, eliminate race conditions, or prove that all dependencies are secure.

These controls should be evaluated as separate layers rather than treated as a single guarantee that arbitrary application code is safe.

## 10. Implementation Detail to Review

In `_build_install_script()`, the current implementation appends the inline Python SBOM-generation command twice.

As written, the generated shell script can execute SBOM generation twice during a successful staging run. This is redundant and should be reviewed. The documentation records the current behavior rather than assuming that the duplicate command has already been removed.

## 11. Related CI Modules

| Module | Responsibility |
|---|---|
| `dependency_mgt.py` | Dispatches dependency staging to the runtime-specific manager. |
| `python_mgt.py` | Prepares, audits, and records the Python dependency environment. |
| `python_handler.py` | Integrates Python-specific behavior with KUBAPP CI. |
| `run_ci.py` | Orchestrates dependency installation, CI checks or scripts, extra checks, and the build stage. |
| `command_policy.py` | Applies configured command-validation rules. |
| `reuse.py` | Provides shared command-execution and file-content utilities. |
| `platform_decision.py` | Provides the `KUBAPP_DECISION` interface used by the handler. |
| `ai_analysis.py` | Provides the `analyze_data` interface used for manifest and Dockerfile analysis. |

## 12. Summary

KUBAPP's Python runtime implementation separates runtime-specific CI behavior from dependency preparation. `PythonHandler` coordinates the CI stages, while `python_mgt.py` prepares and audits dependencies in a resource-constrained Podman container, generates an SBOM, and returns a staged environment for subsequent CI execution.
The distinction between dependency staging, component-command execution, and platform-level Docker builds is important when evaluating the security model. Each has its own execution path and boundary, and the guarantees of one should not automatically be attributed to the others.
