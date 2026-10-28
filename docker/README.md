# KUBAPP Docker Applications

The `docker/` directory contains the applications and components managed by KUBAPP.

KUBAPP discovers application components, validates their configuration, identifies their runtime, and processes them through its CI/CD workflow. Applications provide the required files and configuration; KUBAPP handles discovery, validation, packaging, and delivery through the platform workflow.

## 1. Application Contract

Each application root must:

- Use a directory name ending in `_app`.
- Contain a `Dockerfile`.
- Contain a `ci.yml`, directly or within a nested component directory.

Optional files include:

- `kubapp.yml` — deployment and runtime configuration.
- `ci_secrets.yml` — CI-specific secrets, when required.
- `secrets.yml` or `platform_secrets.yml` — platform-level secrets, where supported.
- Application-specific dependency manifests and source code.

KUBAPP discovers application roots using the `_app` naming convention. It then searches each root recursively for `ci.yml` files. Each discovered `ci.yml` identifies a component directory.

A directory without the `_app` suffix is not treated as an application root. An application root without a discoverable `ci.yml` cannot provide a valid component configuration.

For complete file layouts and configuration examples, see [SAMPLES.md](./SAMPLES.md).

## 2. Application Discovery

KUBAPP separates application discovery from configuration validation.

Discovery identifies application roots and their component directories. Validation determines whether each discovered component has the required files and a valid configuration.

A component may be discovered but still fail validation because its runtime declaration, dependency manifests, Dockerfile, configured paths, CI settings, or other required configuration is invalid.

### Nested Components

A single application root can contain multiple components. For example, an application may contain separate API and worker components.

KUBAPP recursively searches the application root for `ci.yml` files and treats each file's parent directory as a component directory.

Each component must have configuration and dependency manifests consistent with its own runtime.

## 3. Configuration Responsibilities

KUBAPP uses separate files for separate responsibilities.

| File | Responsibility |
|---|---|
| `ci.yml` | Defines CI configuration, runtime, file paths, checks, and health-check settings. |
| `kubapp.yml` | Provides application deployment and runtime configuration. |
| `secrets.yml` | Holds encrypted application secrets. |
| `ci_secrets.yml` | Provides the default CI secrets-file name. A different path can be configured in `ci.yml`. |
| `Dockerfile` | Defines how the application container image is built. |
| Dependency manifests | Describe application dependencies and support runtime detection. |

### 3.1 `ci.yml`

The `ci.yml` file describes how KUBAPP should validate and process a component during CI.

It defines the component's runtime, manifest and configuration paths, CI execution mode, configured commands or scripts, additional CI commands, security-related environment-variable names, and health-check settings.

The configuration must satisfy the validation rules implemented by KUBAPP.

The supported runtime must be registered with the platform, and the runtime detected from the configured dependency manifests must agree with the declared runtime.

The currently registered runtime handlers include:

- `python`
- `node`

CI checks can be configured as commands or scripts. These modes must be configured consistently:

- With `use_script: true`, `ci_scripts` must contain at least one supported script path, and `ci_commands` must be omitted or empty.
- With `use_script: false`, CI checks are defined through `ci_commands`; `ci_scripts` may be omitted or empty.

Script paths must be relative to the component directory, point to existing files, and use a supported extension: `.py` or `.sh`.

Additional CI commands are configured through `extra_ci_commands`, which must be a mapping.

The `security_env` field identifies environment-variable names required by security-related checks. It does not supply the corresponding secret values.

The `extra_ci_config` field must contain the required health-check configuration. Its ports, endpoints, and expected HTTP status must match the application's actual behavior.

For valid configuration examples, see [SAMPLES.md](./SAMPLES.md).

### 3.2 `kubapp.yml`

The `kubapp.yml` file provides application deployment and runtime configuration.

Depending on the fields supported by the platform implementation, it may describe compute requirements, application ports, health endpoints, environment configuration, storage, and platform-specific features.

Keep deployment and runtime settings in `kubapp.yml` where supported, rather than using `ci.yml` as a substitute for deployment configuration.

If `kubapp.yml` is explicitly configured through `file_paths.kubapp_file`, the referenced file must exist. Otherwise, KUBAPP uses its default location when looking for the file.

The exact fields accepted by `kubapp.yml` depend on the platform's configuration parser and deployment implementation.

### 3.3 Application Secrets: `secrets.yml`

`secrets.yml` or `platform_secrets.yml` is used for application secrets managed through the application's configuration and deployment workflow.

Repository-managed secrets must be encrypted before they are committed. KUBAPP's repository workflow uses SOPS for encrypted secrets.

Follow the repository's established activation and encryption process, and ensure the required encryption configuration is in place.

Never commit plaintext credentials, API keys, database passwords, or other sensitive values.

For setup instructions, see [SOPS.md](../SOPS.md).

### 3.4 CI Secrets: `ci_secrets.yml`

`ci_secrets.yml` is the default CI secrets-file name used by the CI discovery and validation configuration.

A different relative path can be configured through `file_paths.secret_file` in `ci.yml`.

CI secrets must remain distinct from application secrets. Supply credentials only to CI operations that need them, and manage their values securely.

The presence of a configured secrets-file path does not, by itself, establish how or when its contents are loaded. That behavior depends on the relevant CI implementation.

### 3.6 Application Files and Dependency Manifests

Application source files and dependency manifests remain specific to the application's language and build system.

KUBAPP does not require every application to use the same framework or source layout. However, its runtime must be supported by the current CI implementation, and the appropriate dependency manifests must be available for runtime detection and validation.

Manifest paths can be configured through `file_paths.manifest_files`. Configured paths must be relative to the component directory and must resolve within that directory.

## 4. Secrets and Security

KUBAPP distinguishes between three secret categories:

- **Application secrets:** `secrets.yml` or `platform_secrets.yml`
- **CI secrets:** `ci_secrets.yml` by default, configurable through `file_paths.secret_file`

These files serve different purposes and must not be assumed to be interchangeable.

Use SOPS to encrypt repository-managed secrets according to the repository's established setup and activation process. Declare required CI environment-variable names through `security_env`, and ensure the corresponding values are supplied securely at execution time.

Application-controlled CI scripts and commands must be treated as code that requires appropriate validation and execution controls. A valid `ci.yml` does not, by itself, guarantee that a command or script is safe.

## 5. Platform Flow

The application delivery workflow follows these high-level stages:

1. Discover application roots ending in `_app`.
2. Search each application root for `ci.yml` files.
3. Load and validate each component's configuration and required files.
4. Identify the component's runtime and select the corresponding handler.
5. Make valid components available to the CI pipeline.
6. Process components through the wider image-packaging and platform-deployment workflow.

The wider workflow handles subsequent delivery stages, including container image processing and deployment to the platform's runtime environment.

Invalid components are reported during validation. Whether validation failures stop the wider pipeline depends on the configured validation and failure modes.

## 6. Adding an Application or Component

Before adding a component, verify that:

- The application root follows the `_app` naming convention.
- Each component has a valid `ci.yml`.
- The declared runtime matches the runtime detected from its manifests.
- The Dockerfile and required manifests exist.
- Configured paths are relative and remain inside the component directory.
- The CI execution mode and its associated scripts or commands are configured consistently.
- Additional CI commands use the required mapping structure.
- Required health-check settings are present and reflect the application's behavior.
- Explicitly configured file paths refer to existing files.
- Application, CI, and platform secrets are handled through their respective workflows.
- Repository-managed secrets are encrypted and managed securely.

For complete, copy-ready application layouts and configuration files, see [SAMPLES.md](./SAMPLES.md).
