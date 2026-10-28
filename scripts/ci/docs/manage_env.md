# KUBAPP CI — Component Environment and Secrets Management

## Overview

`manage_env.py` prepares the environment and execution context required to run a KUBAPP component's CI commands.

It loads a component's optional SOPS-encrypted secrets file, decrypts and validates the secrets, checks required secret declarations, combines the secrets with the current process environment, and creates a `ComponentEnvironment` instance for controlled command execution.

**Primary responsibilities:**
- Load and decrypt component CI secrets using SOPS.
- Parse decrypted YAML and validate its structure.
- Validate secret names and values.
- Enforce required secrets declared through `security_env`.
- Construct the component environment variables.
- Initialize the component's execution context through `ComponentEnvironment`.

This module prepares the environment; it does not itself execute component commands or implement the underlying container isolation.

## Main Functions

### 1. `load_component_secrets(app_name, secret_file)`

Loads and validates a component's CI secrets file.

#### Input handling

If `secret_file` is `None`, the function logs that no secrets file is configured and returns an empty dictionary.

Otherwise, it resolves the supplied path and verifies that it points to a regular file. It then reads the file using UTF-8 encoding.

The function handles the following cases:

| Condition | Behavior |
|---|---|
| No secrets file configured | Returns an empty dictionary. |
| Configured file missing or not a regular file | Logs an error and raises `RuntimeError`. |
| File cannot be read or decoded as UTF-8 | Logs an error and raises `RuntimeError`. |
| File is empty or contains only whitespace | Logs a warning and returns an empty dictionary. |
| SOPS is unavailable | Logs an error and raises `RuntimeError`. |
| SOPS cannot be executed | Logs an error and raises `RuntimeError`. |
| Decryption fails | Logs an error and raises `RuntimeError`. |
| Decrypted YAML is invalid | Logs an error and raises `RuntimeError`. |
| YAML does not contain the expected structure | Logs an error and raises `RuntimeError`. |

#### Decryption

For a nonempty file, the function invokes SOPS using:

` sops --decrypt <secrets-file> `

The command is executed through `subprocess.run()` with captured output and text mode enabled. A nonzero exit code is treated as a decryption failure.

The error message advises checking SOPS configuration and Age key access. The function does not assume that every decryption failure is caused by Age; the underlying cause may vary.

#### YAML structure

The decrypted content is parsed with `yaml.safe_load()`.

The expected structure is a YAML mapping containing a top-level `secrets` mapping.

For example:

```yaml
secrets:
  DATABASE_URL: "example-value"
  API_TOKEN: "example-token"
```

The values above are illustrative, not actual KUBAPP credentials.

The function rejects decrypted content when:
- The YAML document is not a mapping.
- The top-level `secrets` field is missing or is not a mapping.
- A secret name is not a string or does not match the environment-variable naming pattern.
- A secret value is not a string.

Valid secret entries are returned as a dictionary.

**Important:** This function validates the structure and types of the secrets. It does not independently verify the security or correctness of the secret values.

### 2. `prepare_component_environment(...)`

Creates the environment and execution context for a component.

Parameters:

| Parameter | Purpose |
|---|---|
| `app_name` | Identifies the component in logs and error messages. |
| `component_dir` | Component directory passed to `ComponentEnvironment`. |
| `secret_file` | Optional path to the component's encrypted secrets file. |
| `security_env` | List of environment-variable names that must be provided as nonempty secrets. |
| `execution_image` | Container image required by `ComponentEnvironment`. |
| `runtime` | Runtime identifier required by `ComponentEnvironment`. |

The function performs the following steps.

#### Step 1: Validate `security_env`

If `security_env` is `None`, it is treated as an empty list.

Any other value must be a list. Each item must be a string matching the environment-variable naming pattern:

`^[A-Za-z_][A-Za-z0-9_]*$`

Duplicate variable names are rejected.

This prevents malformed declarations and ambiguous repeated secret requirements.

#### Step 2: Verify secrets-file configuration

If `security_env` declares one or more required secrets but `secret_file` is `None`, preparation fails.

The function then calls `load_component_secrets()` to obtain the validated secrets dictionary.

If required secrets were declared but the returned dictionary is empty, preparation also fails.

#### Step 3: Verify required secret values

Each variable listed in `security_env` must have a nonempty value in the loaded secrets dictionary.

A missing or empty required value causes a `RuntimeError`.

This check uses Python truthiness, so an empty string is rejected. Whitespace-only strings are truthy and therefore are not rejected by this particular check.

The function does not require every entry in the secrets file to appear in `security_env`. The list identifies required secrets; it is not an allowlist of every secret that may be loaded.

#### Step 4: Construct the component environment

The function starts with a copy of the current process environment:

`os.environ.copy()`

It then overlays the loaded component secrets:

`component_env.update(secrets)`

Consequently, if a secret has the same name as an existing host environment variable, the secret value takes precedence.

The resulting environment contains the inherited process environment plus the loaded secrets.

**Security consideration:** Copying the entire process environment means the component environment may include variables unrelated to the component, potentially including credentials or other sensitive values. The function does not filter the inherited environment to an explicit allowlist.

#### Step 5: Create the execution context

The function constructs a `ComponentEnvironment` instance using:
- The application name.
- The component directory.
- The combined environment mapping.
- The execution image.
- The runtime.

The `ComponentEnvironment` constructor performs its own validation and initializes the execution context.

If initialization succeeds, the function logs a success message and returns the `ComponentEnvironment` object.

If initialization fails, the exception propagates to the caller.

## Secrets and Execution Flow

The overall preparation flow is:

1. Receive the component's configuration.
2. Validate the `security_env` declaration.
3. Load the configured secrets file.
4. Decrypt the file using SOPS.
5. Parse and validate the decrypted YAML.
6. Verify that all required secret variables are present and nonempty.
7. Merge the secrets into a copy of the process environment.
8. Initialize `ComponentEnvironment`.
9. Return the prepared execution context to the caller.

The function does not execute component-controlled commands during this process.

## Security Boundaries and Limitations

| Area | Behavior | Limitation |
|---|---|---|
| Secrets at rest | Uses SOPS to decrypt the configured file. | Encryption and key-management security depend on the SOPS configuration and key-access controls. |
| Secrets-file validation | Checks that the configured path resolves to a regular file. | Does not restrict the file to a particular trusted directory. |
| YAML parsing | Uses `yaml.safe_load()`. | Safe parsing does not validate the business meaning or appropriateness of secret values. |
| Secret names | Validates names against an environment-variable pattern. | Valid names are not necessarily authorized names. |
| Required secrets | Rejects missing or empty required values. | Whitespace-only values pass the current nonempty check. |
| Environment inheritance | Copies `os.environ` and overlays component secrets. | Unrelated host environment variables may be exposed to the component. |
| Secret output | Logs status messages without intentionally logging secret values. | This function alone does not guarantee that downstream commands or processes will never print secrets. |
| Command isolation | Creates a `ComponentEnvironment`. | Actual filesystem, network, and resource restrictions depend on the execution backend. |

### Secret exposure considerations

Although this module does not intentionally print decrypted secret values, the returned execution environment contains those values.

Any component command receiving this environment may be able to read the secrets available to it. Therefore, the set of secrets and other environment variables passed into component execution should be treated as part of the CI security boundary.

SOPS protects the encrypted file at rest, but decryption makes the plaintext available to the running process. Access to decryption keys, the CI runner, and the resulting environment must therefore be controlled separately.

## Error Handling and Logging

The module uses `ci_log()` to record preparation progress and failures.

Log messages cover:
- Missing or empty secrets files.
- Decryption attempts and failures.
- Invalid YAML or secret mappings.
- Invalid secret names or values.
- Missing required secrets.
- Successful secret validation.
- Successful execution-context preparation.

Most validation and decryption failures are converted into `RuntimeError` exceptions. Exceptions raised while constructing `ComponentEnvironment` are not caught by `prepare_component_environment()` and propagate to the caller.

This allows upstream CI orchestration to detect failed preparation rather than treating an invalid environment as successfully initialized.

## Relationship to Other CI Modules

| Module | Responsibility |
|---|---|
| `reuse.py` | Supplies `ci_log()` for structured CI logging. |
| `component_execution_env.py` | Validates the environment and prepares the component-command execution boundary. |
| `podman_execution.py` | Implements the lower-level container execution behavior. |
| `validate.py` | Validates application configuration, including configured CI settings. |
| `run_ci.py` | Coordinates CI execution and invokes the configured runtime and command-handling flow. |

## Summary

`manage_env.py` bridges component configuration and controlled CI execution. It decrypts and validates SOPS-managed secrets, checks required secret declarations, constructs the environment passed to component execution, and initializes `ComponentEnvironment`.

