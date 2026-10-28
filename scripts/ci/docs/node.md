# KUBAPP CI — Node.js Runtime and Dependency Management

## 1. Overview

KUBAPP's Node.js runtime implementation is divided between two modules:

- **`node_handler.py`** — Integrates Node.js applications into the CI pipeline, including dependency preparation, linting, security analysis, unit tests, and optional Docker image builds.
- **`node_mgt.py`** — Prepares npm dependencies inside a Podman container, runs the npm vulnerability audit, validates the generated software bill of materials (SBOM), and publishes the SBOM to GitOps state.

The shared `dependency_mgt.py` module dispatches dependency preparation to the appropriate runtime-specific manager.

The intended flow is:

1. KUBAPP discovers and validates a Node.js component.
2. `NodeHandler` checks the application manifest, lockfile, execution image, and component execution environment.
3. The package manifest is analyzed through `analyze_data()` and `KUBAPP_DECISION()`.
4. `stage_dependency()` dispatches the request to `stage_node_dependency()`.
5. The dependency manager prepares a temporary copy of the component inside a Podman container.
6. `npm ci` installs the locked dependencies.
7. `npm audit --audit-level=low` checks the installed dependency tree against npm's vulnerability data.
8. The installed `node_modules` directory is copied into a separate staging directory.
9. An SBOM is generated from `package-lock.json`, validated, and published to GitOps state.
10. The component execution environment is configured to use the staged dependencies.
11. The CI runner executes the configured checks and optional build stage.

These modules coordinate dependency preparation and CI execution. The actual security guarantees depend on the container runtime, command policy, dependency configuration, and the behavior of the surrounding execution environment.

## 2. Required Node.js Files

Node.js dependency staging requires two files.

| File | Purpose |
|---|---|
| `package.json` | Declares the application's package metadata and dependencies. |
| `package-lock.json` | Records the resolved npm dependency tree used for reproducible installation. |

The manifest must be named `package.json`, and the lockfile must be named `package-lock.json`.

Both files must exist inside the component directory. The manager resolves their paths and verifies that they remain within that directory.

The implementation also checks that:

- `package.json` contains a JSON object.
- `package-lock.json` contains a JSON object.
- `package.json` declares a nonempty package name.
- If the lockfile declares a package name, it matches the manifest's package name.
- `package-lock.json` declares an integer `lockfileVersion`; booleans are rejected.

The lockfile must be supplied to `NodeHandler` through `extra_manifests`. If it is missing, dependency preparation fails.

**KUBAPP does not fall back to `npm install` when the lockfile is missing.** This implementation deliberately requires a committed npm lockfile and uses `npm ci`.

## 3. NodeHandler

`NodeHandler` connects the Node.js runtime to KUBAPP's shared CI runner.

### 3.1 Initialization

The handler accepts configuration including:

- Application name and component directory.
- Parent directory and runtime.
- Primary manifest and additional manifests.
- Optional Dockerfile.
- CI commands and extra CI commands.
- Extra CI configuration and security environment settings.
- Optional environment variables.
- Component execution environment.

The component directory is resolved to an absolute path during initialization.

When a component execution environment is supplied, the handler copies its environment variables and obtains its configured execution image.

The handler also maintains `staged_dependencies`, which is populated after successful dependency preparation.

### 3.2 Dependency Installation

`install_dependencies()` prepares the npm dependency environment before the remaining CI stages run.

The method performs these checks:

1. Confirms that the component directory exists and is a directory.
2. Confirms that a package manifest is configured.
3. Resolves a relative manifest against the component directory.
4. Confirms that the manifest file exists.
5. Finds `package-lock.json` in `extra_manifests`.
6. Confirms that the lockfile exists.
7. Confirms that an execution image is configured.
8. Confirms that the component execution environment is available.

The method then:

1. Reads the package manifest using `collect_content()`, restricting the read to the component directory.
2. Passes the manifest content to `analyze_data()` with the artifact type `module`.
3. Evaluates the analysis result through `KUBAPP_DECISION()`.
4. Calls `stage_dependency()` with the Node.js runtime, application name, component directory, manifest, lockfile, and execution image.
5. Registers the returned staging directory using `component_environment.set_dependency_environment()`.
6. Logs the prepared dependency environment.

The analysis and decision calls precede dependency staging. Their precise enforcement behavior depends on their implementations.

### 3.3 Linting

`lint()` retrieves the configured `lint` command from `ci_commands`.

It then:

1. Rejects a missing or empty command.
2. Verifies that the command is a nonempty list of nonempty strings.
3. Validates the command using `ensure_command_is_safe(command, "node")`.
4. Executes the command through `run_component_command()`.
5. Uses the component directory as the working directory.

A command failure prevents the method from reporting success.

### 3.4 Security Analysis

`security_analysis()` retrieves the configured `security` command, validates its structure, checks it against the Node.js command policy, and executes it through the component execution boundary.

The handler does not itself implement a separate source-code security scanner in this method. The actual checks depend on the configured command and the tool it invokes.

This stage is distinct from the npm dependency audit performed during dependency preparation.

### 3.5 Unit Tests

`unit_tests()` retrieves the configured `test` command, verifies its structure, applies the Node.js command policy, and executes it through `run_component_command()`.

The method reports success only after the command completes successfully.

### 3.6 Docker Image Build

`build_from_dockerfile()` handles the optional Docker image build.

If no Dockerfile is configured, the method logs that the build is being skipped and returns `None`.

Otherwise, it:

1. Reads the Dockerfile through `collect_content()`, restricting the read to the component directory.
2. Passes the Dockerfile content to `analyze_data()` with the artifact type `dockerfile`.
3. Evaluates the analysis result through `KUBAPP_DECISION()`.
4. Obtains a commit identifier through `get_latest_commit_id()`.
5. Constructs an image tag in the form `<app_name>:<commit_id>`.
6. Runs `docker build` through `run_platform_command()`.
7. Inspects the resulting image with `docker image inspect`.
8. Returns the image name after successful completion.

Docker image construction is treated as a platform operation rather than a component-command operation.

**Important distinction:** The Docker build is separate from the Podman dependency-staging container. The resource restrictions on the staging container do not automatically apply to the Docker build.

### 3.7 CI Runner Integration

`run_ci()` constructs a `CIRunner` with the handler, `use_script` setting, and optional CI script list. It then delegates execution to `runner.run()`.

The shared runner determines the order of dependency installation, configured CI checks or scripts, extra checks, and the final build stage.

See `run_ci.md` for the shared runner's execution flow.

## 4. Node.js Dependency Staging

The `node_mgt.py` module provides the runtime-specific dependency preparation implementation.

### 4.1 Entry Point

The main entry point is:

`stage_node_dependency(...)`

It accepts:

- `app_name`
- `component_dir`
- `manifest`
- `lockfile`
- `execution_image`
- Optional `staging_root`

It returns the path to the prepared staging directory.

The function validates the application name and execution image, resolves the component and file paths, checks the manifest and lockfile, validates the package metadata, and prepares a unique staging directory.

Application names must match the configured pattern:

`[A-Za-z0-9][A-Za-z0-9_.-]*`

This restriction is used to keep names compatible with the staging and SBOM publication paths.

### 4.2 Runtime Dependency Configuration

The manager imports `RUNTIME_DEPENDENCY_CONFIG` from `variables.py`.

For Node.js, the configuration must provide three nonempty relative paths:

- `dependency_path`
- `executable_path`
- `required_path`

Absolute paths and paths containing a `..` component are rejected.

These values determine which locations inside the staging directory are checked after installation.

The manager requires:

- The configured dependency path to be a directory.
- The configured executable path to be a directory.
- The configured required path to be a file.

This lets the runtime configuration define the expected structure of the prepared Node.js environment instead of hardcoding every validation path inside the manager.

The actual values must be checked in `variables.py`; they should not be inferred from this module alone.

### 4.3 Podman Discovery

`_podman_path()` searches the following locations:

- `/usr/local/bin/podman`
- `/usr/bin/podman`

The selected path must point to a file with at least one executable permission bit.

If neither location qualifies, the manager raises `NodeStagingError`.

This is a fixed-path lookup rather than a general search through the system's `PATH`.

### 4.4 Execution Image Availability

Before creating the staging container, `_ensure_image_available()` checks whether the configured execution image exists locally.

If the image check returns a nonzero status, the manager attempts to pull the image.

Podman execution failures are reported through `NodeStagingError`, with available command output included in the error.

Because any nonzero image-existence result triggers a pull attempt, the implementation does not distinguish a missing image from every other possible reason for that check to fail.

## 5. Staging Container Configuration

Dependency installation and auditing take place inside a Podman container created from the configured Node.js execution image.

The container uses the following principal restrictions:

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
| Component source | Mounted at `/workspace:ro` | Provides read-only access to the component source. |
| Dependency staging | Mounted at `/opt/kubapp-dependencies:rw` | Stores the prepared dependencies and SBOM. |
| npm cache | `npm_config_cache=/tmp/npm-cache` | Directs npm's cache into the container's temporary filesystem. |
| npm update notification | `npm_config_update_notifier=false` | Disables npm's update notification. |

The container uses `/workspace` as its working directory and runs the generated shell script through `/bin/sh -c`.

The script creates a writable temporary copy of the application under:

`/tmp/kubapp-node-build`

Installation occurs in this copy rather than in the read-only component mount. The resulting `node_modules` directory is then copied into the writable staging mount.

**Network access is not explicitly disabled.** The image pull and npm operations may require network connectivity. The container configuration does not use `--network=none`.

These settings provide useful containment, but they do not independently prove complete isolation. Their effectiveness depends on the host kernel, Podman configuration, and runtime enforcement.

## 6. npm Installation and Vulnerability Audit

The generated installation script uses `set -eu` and chains its operations with `&&`.

### 6.1 Create a Temporary Build Directory

The script removes any existing `/tmp/kubapp-node-build` directory, recreates it, and copies the contents of `/workspace` into it.

This allows npm to write installation artifacts without modifying the original component directory through the read-only mount.

### 6.2 Install Locked Dependencies

The script runs:

`npm ci --no-fund --no-audit`

This installs dependencies using the lockfile and avoids running the audit as part of the installation command.

The explicit audit follows as a separate step, allowing the implementation to apply its own audit threshold.

Using `npm ci` requires a compatible package manifest and lockfile. KUBAPP's earlier validation ensures that both files exist and that their declared package names are compatible when the lockfile contains a name.

### 6.3 Run npm Audit

The script runs:

`npm audit --audit-level=low`

This sets the audit failure threshold to the low severity level. Vulnerabilities reported at that level or higher can cause the command to fail.

The audit depends on npm's vulnerability data and the dependency information available to the audit operation. It is not a source-code security scan and does not prove that an application has no security defects.

### 6.4 Copy Installed Dependencies

After a successful audit, the script verifies that the temporary build's `node_modules` directory exists.

It then copies that directory into the staging directory.

The staged dependencies are prepared separately from the application source so that KUBAPP can subsequently provide them to the component execution environment.

Because the script uses `set -eu` and `&&`, a failed installation or audit prevents the later copy and SBOM-generation steps from completing successfully.

## 7. SBOM Generation

The Node.js SBOM is generated from `package-lock.json` using a JavaScript script executed by Node.js.

The generated file is:

`/opt/kubapp-dependencies/sbom.json`

### 7.1 Application Package Inventory

The SBOM generator reads the copied component's `package-lock.json`.

For lockfiles containing a `packages` object, it records package entries with versions, excluding:

- The empty package path representing the root application.
- Entries marked as links.

For legacy lockfiles that contain a `dependencies` object instead, it recursively collects dependency entries and their versions.

Package inventory entries are keyed by their package paths. Duplicate paths and invalid package versions cause generation to fail.

The generator also rejects an unsupported or incomplete lockfile format and an empty package inventory.

This inventory is based on the lockfile rather than a direct scan of every package installed in `node_modules`.

### 7.2 npm Tool Metadata

The generator obtains the npm version by running:

`npm --version`

It records that version under:

`kubapp_data.section.tools["npm-audit"]`

Despite the metadata key being named `npm-audit`, the value recorded by this code is the installed **npm version**, not the version of a separate audit executable.

### 7.3 SBOM Structure

The generated JSON contains two main sections:

- `app_section` — Application name, description, runtime, and package inventory.
- `kubapp_data` — KUBAPP dependency-audit metadata, including the recorded npm version and a separate package inventory object.

The generator writes the JSON with indentation and a trailing newline. It uses exclusive file creation, so an already existing SBOM at the target staging path causes the write to fail rather than silently overwrite it.

## 8. SBOM Validation and Publication

After the staging container finishes, `_publish_sbom()` validates the generated SBOM before publishing it.

The validation checks include:

- The SBOM is a JSON object.
- The application name matches the requested application.
- The runtime is `node`.
- The application package inventory is an object and is not empty.
- The KUBAPP metadata section exists.
- The tool metadata contains a truthy `npm-audit` value.
- The KUBAPP package inventory is an object.

The publication destination is:

`gitops/state/sbom/<app_name>.json`

The path is resolved relative to the repository structure determined from the module's location.

Publication uses a temporary file in the destination directory, writes formatted JSON, flushes and synchronizes the file, and atomically replaces the destination with `os.replace()`.

This reduces the risk of readers observing a partially written SBOM. It does not provide concurrent-writer coordination or guarantee that the published SBOM corresponds to the latest successful CI run.

If SBOM validation or publication fails, the dependency manager raises `NodeStagingError`.

## 9. Staging Validation and Metadata

After the Podman operation succeeds, the manager checks that:

1. `sbom.json` exists in the staging directory.
2. The configured dependency directory exists.
3. The configured executable directory exists.
4. The configured required file exists.

The manager then writes `.kubapp-staging-info` with the following information:

- Execution image.
- Manifest path.
- Lockfile path.
- Dependency directory.
- `package_manager=npm`.
- `dependency_audit=passed`.
- `installation_location=prepared_container`.

The metadata records the result of the staging process. It is not independently verified proof of every security property of the environment.

The SBOM is published after the staging metadata is written. If publication fails, the manager's exception handler removes the staging directory.

## 10. Cleanup and Error Handling

`NodeStagingError` is used to report failures specific to Node.js dependency preparation.

The Podman wrapper captures standard output and standard error, checks the command's exit status, and includes available output in its error message when the command fails.

If an exception occurs during staging, the manager removes the staging directory using `shutil.rmtree(..., ignore_errors=True)` and re-raises the exception.

This cleanup removes the temporary staging directory. It does not roll back an SBOM that was already published if a later operation were added after publication and subsequently failed.

The handler and shared CI runner generally allow errors to propagate to the higher-level orchestration layer.

## 11. Security Boundaries and Limitations

The implementation establishes several useful controls, but each has a defined scope.

### Controls implemented

- Requires both `package.json` and `package-lock.json`.
- Rejects unsupported manifest and lockfile filenames.
- Resolves and checks manifest and lockfile containment within the component directory.
- Checks the package name and lockfile version metadata.
- Uses `npm ci` instead of falling back to `npm install`.
- Runs npm dependency auditing with a low-severity failure threshold.
- Performs installation in a temporary copy of the component.
- Mounts the original component directory read-only into the staging container.
- Applies container resource limits and a read-only root filesystem.
- Keeps staged dependencies in a separate directory.
- Validates the expected staged paths before returning the environment.
- Validates SBOM structure and application identity before publication.
- Uses atomic replacement when publishing the SBOM.

### Important limitations

- The staging container does not explicitly disable network access.
- Package installation executes dependency lifecycle behavior supported by npm; the code does not explicitly disable lifecycle scripts.
- A read-only source mount prevents writes through that mount but does not prevent code from executing inside the container.
- Container restrictions depend on host and runtime enforcement.
- The command policy is not a complete sandbox or a general allowlist.
- The AI decision flow depends on the implementations of `analyze_data()` and `KUBAPP_DECISION()`.
- The configured CI commands determine which linting, security, and testing tools actually run.
- The SBOM package inventory is derived from the lockfile; it is not a direct attestation of the exact contents of the installed `node_modules` directory.
- The recorded `npm-audit` tool metadata is the npm version, not a distinct npm audit tool version.
- The optional Docker build is a separate platform operation and is not automatically confined by the staging container's restrictions.

These layers should be evaluated independently rather than treated as a single guarantee that arbitrary application code is safe.

## 12. Related CI Modules

| Module | Responsibility |
|---|---|
| `dependency_mgt.py` | Dispatches dependency staging to the runtime-specific manager. |
| `node_mgt.py` | Prepares, audits, and records the Node.js dependency environment. |
| `node_handler.py` | Integrates Node.js-specific behavior with KUBAPP CI. |
| `run_ci.py` | Orchestrates dependency installation, CI checks or scripts, extra checks, and the build stage. |
| `command_policy.py` | Applies configured command-validation rules. |
| `reuse.py` | Provides shared command-execution and file-content utilities. |
| `platform_decision.py` | Provides the `KUBAPP_DECISION` interface used by the handler. |
| `ai_analysis.py` | Provides the `analyze_data` interface used for manifest and Dockerfile analysis. |
| `variables.py` | Supplies the runtime dependency path configuration. |

## 13. Summary

KUBAPP's Node.js runtime implementation separates CI orchestration from dependency preparation. `NodeHandler` coordinates the runtime-specific CI stages, while `node_mgt.py` installs locked npm dependencies inside a resource-constrained Podman container, audits the dependency tree, generates an SBOM, and returns a staged dependency environment.
The use of a committed lockfile and `npm ci` makes dependency installation more predictable. However, network access, npm lifecycle execution, runtime enforcement, SBOM provenance, and the separate Docker build remain important parts of the wider security model.
