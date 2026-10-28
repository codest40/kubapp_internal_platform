# `validate.py` — Application Configuration Validation

## Purpose

`validate.py` validates application candidates discovered by `detect_runtime.py` before they enter the CI build stage.

It checks runtime declarations, manifest files, required configuration files, custom CI scripts, command configuration, security environment settings, and container health-check configuration.

The module returns validated application records to `dependency_abstractor.py`, which decides whether the build stage can proceed according to `STRICT_MODE`.

## 1. Main Responsibilities

| Function | Responsibility |
|---|---|
| `validate_app()` | Validates one discovered application or component and returns a normalized record when successful. |
| `validate_all_apps()` | Validates all candidates, collects successful records, and calculates the aggregate validation signal. |
| `validate_apps()` | Public wrapper around `validate_all_apps()`. |
| `_validate_runtime_config()` | Checks the declared runtime and confirms that a handler is registered. |
| `_validate_manifest_paths()` | Checks manifest names and files, detects the runtime, and verifies runtime consistency. |
| `_validate_execution_config()` | Validates custom-script and CI-command configuration. |
| `_validate_ci_script_paths()` | Checks custom-script paths, containment, file existence, and supported extensions. |
| `_validate_healthcheck()` | Validates the required health-check configuration. |
| `_validate_security_env()` | Validates the `security_env` list and rejects duplicate entries. |
| `_validate_file_paths_config()` | Validates the structure and supported keys of `file_paths`. |
| `print_invalid_apps()` | Logs application validation failures and their associated errors. |

Additional helper functions validate strings, string lists, port numbers, files, application directories, and discovery records.

## 2. Validation Inputs

The validator consumes candidate records produced by `detect_runtime.py`.

These records include the application and component directories, parsed `ci.yml` configuration, discovered file paths, detected runtimes, and any errors encountered during discovery.

The validator checks that the candidate structure is usable before relying on its contents.

If discovery or runtime detection has already recorded errors, those errors are incorporated into the validation process.

## 3. Runtime Validation

The `runtime` field in `ci.yml` must be a nonempty string.

The validator strips surrounding whitespace, converts the value to lowercase, and checks it against the runtime names derived from `MANIFESTS` in `variables.py`.

It then calls `get_runtime_handler()` to ensure that a handler is registered for the declared runtime.

A runtime can therefore fail validation for two distinct reasons:

- It is not recognized by the configured manifest-to-runtime mappings.
- It is recognized by those mappings but has no registered CI handler.

The current handler registry in `detect_runtime.py` contains Python and Node.js handlers.

## 4. Manifest Validation

The validator checks that discovered manifest paths form a list and that at least one manifest is available.

Each manifest must:

- Be a string or `Path` object.
- Have a filename recognized by `MANIFESTS` or `EXTRA_MANIFESTS`.
- Exist as a file.
- Be nonempty.

The validator distinguishes between runtime manifests and supporting manifests.

### Runtime manifests

Runtime manifests are mapped through `MANIFESTS`. They establish the application's runtime.

The validator rejects configurations where:

- No valid runtime manifest is found.
- Runtime manifests identify multiple different runtimes.
- The detected runtime differs from the runtime declared in `ci.yml`.

The first valid runtime manifest is returned as the primary manifest.

### Supporting manifests

Supporting manifests are mapped through `EXTRA_MANIFESTS`. They supplement runtime configuration but cannot establish the runtime on their own.

The validator checks that each supporting manifest belongs to the detected runtime.

For example, a supporting manifest associated with Node.js should not be accepted as a supporting manifest for a Python component.

**Recognizing a manifest filename does not validate its contents.** This stage checks the file's identity, existence, size, and relationship to the declared runtime; it does not perform a complete semantic analysis of the manifest.

## 5. File Path Configuration

The optional `file_paths` mapping supports these keys:

| Key | Purpose | Requirement |
|---|---|---|
| `manifest_files` | Explicitly configure manifest paths | Must be a nonempty path string or a nonempty list of nonempty strings. |
| `docker_file` | Configure the Dockerfile path | If supplied, must be a nonempty string. A Dockerfile is required during validation. |
| `kubapp_file` | Configure the platform configuration file | If supplied, must be a nonempty string. The file is required when this key is explicitly configured. |
| `secret_file` | Configure the component secrets file | If supplied, must be a nonempty string. The file is required when this key is explicitly configured. |

Unknown `file_paths` keys are rejected.

The validator also checks the resolved file paths discovered earlier. Required files must exist as files and must not be empty.

A configured `kubapp.yml` or `ci_secrets.yml` is therefore not required merely because its default filename exists in the code. It becomes required when the corresponding path key is explicitly configured.

The validator relies on `detect_runtime.py` for path resolution and containment checks.

## 6. CI Execution Configuration

The validator checks `use_script`, `ci_scripts`, `ci_commands`, and `extra_ci_commands`.

### `use_script`

`use_script` must be a Boolean. If it is missing, the default is `False`.

### Custom scripts

When `use_script` is `True`:

- `ci_scripts` must be a nonempty list of nonempty strings.
- `ci_commands` must be omitted, `None`, or an empty mapping.
- Each script path is checked for existence and containment within the component directory.
- Absolute paths and paths that escape the component directory are rejected.
- Only `.py` and `.sh` script extensions are accepted.

When `use_script` is `False`, `ci_scripts` may be an empty list, and `ci_commands` may be omitted or supplied as a mapping.

These checks validate the configured script paths and execution configuration. They do not inspect the full contents of each script for malicious behavior.

### Additional commands

`extra_ci_commands` must be a mapping when provided. An omitted or `None` value is normalized to an empty mapping.

The validator checks the configuration's structure. Command-level policy enforcement, where applicable, is handled by other components.

## 7. Security Environment Configuration

The optional `security_env` setting must be a list of nonempty strings.

If it is omitted or set to `None`, the validator treats it as an empty list.

Duplicate entries are rejected.

This validates the list's structure and uniqueness. It does not establish that every referenced environment variable exists, that its value is secret, or that its eventual use is secure. Environment preparation and secret handling are performed elsewhere.

## 8. Health-Check Validation

The validator requires `extra_ci_config` to be a mapping containing a `healthcheck` mapping.

The health-check configuration must include:

| Field | Requirement |
|---|---|
| `app_port` | Integer between 1 and 65535. |
| `host_port` | Integer between 1 and 65535. |
| `endpoints` | Nonempty list of nonempty strings; each endpoint must begin with `/`. |
| `expected_status` | Integer HTTP status code between 100 and 599. |

Boolean values are rejected as port numbers and as expected status codes, despite Python treating Booleans as a subclass of integers.

The implementation requires `expected_status` to be present and valid. It does not apply the `200` default here; that default is applied later by the orchestrator when retrieving the field. Consequently, a missing `expected_status` is rejected during validation before that later default can take effect.

The validator checks the configuration's structure and numeric ranges. It does not make HTTP requests or establish that an endpoint responds correctly. Those checks are performed by `container.py` during CI execution.

## 9. Application and Component Names

`validate_app()` validates both the application root and component directory.

When the component directory differs from the application root, the validator derives a component-specific name from the nested path and combines it with the application root name.

This allows nested components to receive distinct identifiers in the normalized validation records.

The validator also checks the discovery record, configuration file, file paths, runtime, manifests, and execution settings before returning a successful result.

## 10. Validation Results

A successful `validate_app()` call returns a normalized record containing fields such as:

- `app`
- `app_dir`
- `component_dir`
- `runtime`
- `manifest`
- `manifest_files`
- `ci_file`
- `dockerfile`
- `platform_file`
- `secret_file`
- `use_script`
- `ci_scripts`
- `ci_commands`
- `extra_ci_commands`
- `extra_ci_config`
- `security_env`

Path fields are returned as `Path` objects where appropriate. Optional platform and secret file paths are returned as `None` when not configured.

If validation fails, `validate_app()` logs the errors and returns `None`.

### Aggregate result

`validate_all_apps()` processes all supplied candidates and returns a mapping with:

- `valid_apps`: the list of successfully validated application records.
- `signal`: a Boolean indicating whether the overall validation succeeded.

The signal is calculated as follows:

| Outcome | `signal` |
|---|---|
| No valid applications | `False` |
| At least one valid application and at least one invalid application | `False` |
| At least one valid application and no invalid applications | `True` |

If application discovery raises `RuntimeError`, the function returns an empty `valid_apps` list and a failure signal.

## 11. Interaction with `STRICT_MODE`

The validator itself does not read `STRICT_MODE` or decide whether the overall CI build should proceed.

That decision belongs to `dependency_abstractor.py`.

- With strict mode enabled, an unsuccessful aggregate validation signal blocks the build stage.
- With strict mode disabled, the orchestrator can continue with the applications in `valid_apps`, provided that list is not empty.

This separates the validation result from the orchestration policy that determines how to respond to it.

## Important Distinction

`validate.py` validates application configuration and produces normalized records for the CI workflow. It does not install dependencies, execute custom scripts, build Docker images, publish images, or test live application endpoints.

Those operations are delegated to the runtime handlers and other CI components after validation succeeds.
