# `detect_runtime.py` — Application Discovery and Runtime Detection

## Purpose

`detect_runtime.py` discovers application components under KUBAPP's `docker/` directory, reads their CI configuration, identifies relevant files, and detects runtimes from manifest filenames.

It also provides a registry for selecting the runtime-specific handler used by the CI orchestrator.

**Discovery and runtime detection do not perform the full application validation process.** That responsibility belongs to `validate.py`.

## 1. Configuration and Constants

| Constant | Purpose |
|---|---|
| `PROJECT_ROOT` | Project root resolved through `reuse.get_root()`. |
| `DOCKER_DIR` | Application discovery directory: `<PROJECT_ROOT>/docker`. |
| `CI_FILENAME` | CI configuration filename: `ci.yml`. |
| `CI_SECRET_FILE` | Default secrets filename: `ci_secrets.yml`. |
| `DOCKERFILE_FILE` | Default Dockerfile name: `Dockerfile`. |
| `KUBAPP_FILE` | Default platform configuration filename: `kubapp.yml`. |
| `VALID_APP_SUFFIX` | Required application-root suffix: `_app`. |
| `HANDLERS` | Mapping of supported runtime names to handler classes. |

The current handler registry contains:

- `python` → `PythonHandler`
- `node` → `NodeHandler`

Although `MANIFESTS` may recognize additional runtime manifest types, a recognized manifest does not automatically mean that a corresponding CI handler is available.

## 2. Application Root Discovery

`discover_app_roots()` examines the immediate children of `DOCKER_DIR`.

It selects directories whose names end in `_app`, sorts them by path, and returns the resulting list.

For example:

```text
docker/
├── api_app/
├── frontend_app/
└── worker_app/
```

If the Docker directory does not exist, is not a directory, or contains no matching application directories, the function raises `RuntimeError`.

Errors encountered while listing the directory are also reported as runtime errors.

**Only the root application directories are selected at this stage.** Nested component discovery happens afterward.

## 3. Discovering Components and CI Configuration

`discover_apps()` searches recursively within each application root for files named `ci.yml`.

Each discovered `ci.yml` creates a candidate component whose directory is the directory containing that file.

For example:

```text
docker/
└── commerce_app/
    ├── ci.yml
    ├── requirements.txt
    ├── Dockerfile
    └── services/
        └── billing/
            ├── ci.yml
            ├── pyproject.toml
            └── Dockerfile
```

This structure can produce separate candidates for the root application and the nested billing component.

If an application root contains no `ci.yml` anywhere below it, the script still creates a candidate for the application root. That candidate will record the missing configuration as a discovery error.

Candidates are sorted by their paths relative to `DOCKER_DIR`.

### Reading `ci.yml`

`_read_ci_config()` uses `yaml.safe_load()` to parse the configuration.

The parsed result must be a dictionary representing a YAML mapping. File access errors, decoding errors, YAML parsing errors, and non-mapping results are recorded as discovery errors.

When the configuration cannot be read or parsed, discovery still returns a record with the error information instead of immediately terminating the entire discovery process.

## 4. Discovering Component Files

For each component, `discover_app()` collects paths to the following files:

| File | Configuration key | Default filename |
|---|---|---|
| Manifest files | `file_paths.manifest_files` | Recognized manifests found in the component root |
| Dockerfile | `file_paths.docker_file` | `Dockerfile` |
| Platform configuration | `file_paths.kubapp_file` | `kubapp.yml` |
| Secrets configuration | `file_paths.secret_file` | `ci_secrets.yml` |

When an individual file path is not configured, the script checks for the corresponding default filename in the component root.

For manifest discovery, the script checks root-level files against the recognized names in `MANIFESTS` and `EXTRA_MANIFESTS`.

### Explicit manifest configuration

If `file_paths.manifest_files` is present, its value may be a path string or a list of paths. The script resolves those configured paths rather than performing its normal automatic manifest discovery.

An invalid value produces a discovery error.

An explicitly configured manifest path must be relative to the component directory. The resolved path must remain inside that directory; absolute paths and paths that escape the component directory are rejected.

The script records resolved manifest paths, but the discovery stage does not establish that every configured file exists, is nonempty, or is a valid manifest. Those checks must be handled by the relevant validation or execution logic.

### Single-file configuration

The `docker_file`, `kubapp_file`, and `secret_file` entries accept a single relative path string.

Invalid path values or paths that escape the component directory are recorded as errors.

The `required` parameter is passed as `True` for the Dockerfile lookup, but `_discover_single_file()` does not currently use that parameter to enforce file existence. Required-file enforcement therefore must not be assumed from this function alone.

## 5. Runtime Detection

`detect_runtime_from_manifests()` examines the discovered manifest paths and matches their filenames against `MANIFESTS` from `variables.py`.

For example, if `requirements.txt` maps to Python in `MANIFESTS`, that filename identifies the Python runtime.

The function collects detected runtime names in a set and returns them as a sorted list.

Its result has this structure:

```python
{
    "detected_runtimes": ["python"],
    "errors": []
}
```

This example is illustrative; the actual runtime list depends on the manifests and mappings.

Runtime detection is based on filenames, not on parsing the manifest contents or verifying that the application can execute successfully.

If multiple recognized manifests map to different runtimes, the function can return multiple detected runtimes. Any conflict-resolution or consistency rules must be handled by the validation layer or other calling code.

## 6. Discovery Record

`discover_app()` returns a record containing the information collected for a candidate.

Important fields include:

| Field | Meaning |
|---|---|
| `app_dir` | Application root supplied to the discovery function. |
| `component_dir` | Directory treated as the component being discovered. |
| `discovery_errors` | Errors encountered while reading configuration or discovering paths. |
| `ci_file` | Path to the expected `ci.yml`. |
| `ci_config` | Parsed CI configuration, or `None` if parsing failed. |
| `file_paths` | Discovered manifest, Dockerfile, platform configuration, and secrets paths. |
| `detected_runtimes` | Sorted runtime names detected from manifest filenames. |
| `runtime_detection_errors` | Errors reported by runtime detection. |

The discovery record is an intermediate representation. It is not, by itself, proof that a component is ready to build.

## 7. Runtime Handler Selection

`get_runtime_handler(runtime)` returns the registered handler class from `HANDLERS`, or `None` if the runtime is not registered.

Currently, the registry supports:

| Runtime | Handler |
|---|---|
| Python | `PythonHandler` |
| Node.js | `NodeHandler` |

The orchestrator uses this function to select the handler that will execute the component's CI workflow.

A runtime can be detected successfully but still fail later if no corresponding handler is registered.

This distinction matters because `MANIFESTS` describes recognized manifest-to-runtime mappings, whereas `HANDLERS` determines which runtimes have an implementation available through this registry.

## 8. Additional Helper Functions

| Function | Purpose |
|---|---|
| `discover_app_candidates()` | Backward-compatible alias for `discover_apps()`. |
| `detect_app_runtime(app_dir)` | Detects runtimes from recognized manifest filenames directly under a supplied directory. |
| `detect_all_runtimes()` | Returns the discovered candidate records by delegating to `discover_apps()`. |
| `has_runtime(app_dir, runtime)` | Checks whether root-level manifest detection identifies the specified runtime without reporting errors. |
| `detect_apps_by_runtime(runtime)` | Returns discovered candidates matching a runtime, excluding candidates with discovery or runtime-detection errors. |
| `detect_components_by_runtime()` | Groups discovered candidates by their detected runtime, skipping candidates with recorded discovery or runtime-detection errors. |

`detect_app_runtime()` examines only files directly inside the supplied directory; it does not recursively search for manifests.

`detect_all_runtimes()` returns candidate records rather than a simple list of runtime names.

## 9. Error Handling and Boundaries

The discovery code records many component-specific errors so that the caller can inspect candidates even when some files or configurations are invalid.

However, `discover_app_roots()` raises an exception when the overall discovery root is missing or contains no matching application directories.

The distinction is:

- **Root-level discovery failure:** the process cannot establish the application roots to inspect.
- **Component-level discovery failure:** a candidate can still be returned with recorded errors.
- **Runtime detection:** identifies runtimes from recognized filenames.
- **Application validation:** determines whether the discovered application configuration satisfies the platform's requirements.
- **Runtime execution:** requires a registered handler capable of running the CI workflow.

## Summary

`detect_runtime.py` establishes which application components KUBAPP can discover, which configuration and manifest paths are associated with them, and which runtimes their manifest filenames indicate.
It does not build images, install dependencies, run health checks, or independently establish that an application is valid. Those responsibilities belong to subsequent stages of the CI pipeline.
