# KUBAPP CI — Dependency Staging Dispatcher

## 1. Overview

`dependency_mgt.py` is the shared entry point for runtime-specific dependency preparation in KUBAPP CI.

Instead of making the CI runner call each runtime manager directly, this module dispatches dependency staging according to the component's runtime.

Currently supported runtimes are:

- **Python** — handled by `python_mgt.py`.
- **Node.js** — handled by `node_mgt.py`.

The dispatcher provides a common interface while allowing each runtime manager to implement its own installation, auditing, validation, and staging logic.

## 2. Responsibilities

The module is responsible for:

- Validating the requested runtime.
- Normalizing the runtime name.
- Routing Python requests to `stage_python_dependency()`.
- Routing Node.js requests to `stage_node_dependency()`.
- Requiring a lockfile for Node.js dependency staging.
- Rejecting unsupported runtimes with a `DependencyStagingError`.

The dispatcher does not install dependencies itself. The selected runtime manager performs the actual staging operation.

## 3. Dependency Staging Entry Point

The shared entry point is:

`stage_dependency(...)`

It accepts the runtime and common staging parameters, including:

- `runtime`
- `app_name`
- `component_dir`
- `manifest`
- `execution_image`
- Optional `staging_root`
- Optional `lockfile`

The function validates that `runtime` is a nonempty string and normalizes it to lowercase before selecting a manager.

### Python dispatch

For `runtime="python"`, the dispatcher calls:

`stage_python_dependency(...)`

It passes the application name, component directory, manifest, execution image, and optional staging root.

The Python manager supports `requirements.txt` and `pyproject.toml`.

### Node.js dispatch

For `runtime="node"`, the dispatcher first requires a lockfile.

If no lockfile is supplied, it raises `DependencyStagingError` rather than proceeding with dependency preparation.

When a lockfile is available, the dispatcher calls:

`stage_node_dependency(...)`

It passes the application name, component directory, manifest, lockfile, execution image, and optional staging root.

The Node.js manager requires `package.json` and `package-lock.json`.

### Unsupported runtimes

If the normalized runtime is not supported, the dispatcher raises `DependencyStagingError`.

It does not attempt to guess a manager or fall back to another runtime.

## 4. Execution Flow

The dependency staging flow is:

1. The runtime handler invokes `stage_dependency()`.
2. The dispatcher validates and normalizes the runtime.
3. The dispatcher selects the corresponding runtime manager.
4. The runtime manager validates its runtime-specific inputs.
5. The runtime manager prepares and validates the dependency environment.
6. The manager returns the staging directory.
7. The handler registers that directory with the component execution environment.

The dispatcher returns the selected manager's result rather than transforming the returned staging path.

## 5. Error Handling

`DependencyStagingError` is a custom `RuntimeError` used for dispatcher-level failures.

These include:

- A missing or invalid runtime value.
- A missing lockfile for Node.js.
- An unsupported runtime.

Errors raised by the runtime-specific managers can also propagate through the dispatcher. The dispatcher does not silently convert a failed staging operation into a successful result.

This allows the CI orchestration layer to treat dependency preparation failures as failures rather than continuing as if dependencies were ready.

## 6. Security Boundaries

The dispatcher is a routing and validation layer, not an execution sandbox.

It does not itself:

- Create a container.
- Apply CPU, memory, or process limits.
- Install or audit dependencies.
- Validate every runtime-specific file.
- Enforce filesystem isolation.
- Execute component CI commands.

Those responsibilities belong to the runtime-specific managers and the surrounding execution environment.

The dispatcher also does not independently establish that a returned staging directory is secure. The selected manager must enforce its own validation and staging requirements.

## 7. Related Modules

| Module | Responsibility |
|---|---|
| `dependency_mgt.py` | Selects the runtime-specific dependency manager. |
| `python_mgt.py` | Prepares and audits Python dependencies. |
| `node_mgt.py` | Prepares and audits npm dependencies. |
| `python_handler.py` | Integrates Python dependency staging into the CI lifecycle. |
| `node_handler.py` | Integrates Node.js dependency staging into the CI lifecycle. |
| `run_ci.py` | Orchestrates the shared CI execution sequence. |
| `variables.py` | Supplies runtime dependency configuration used by the Node.js manager. |

## 8. Summary

`dependency_mgt.py` provides a common interface for KUBAPP's runtime-specific dependency staging. It validates the runtime selection, enforces the Node.js lockfile requirement, and delegates the actual work to the appropriate manager.
Keeping this dispatcher separate from the runtime implementations makes the shared CI flow simpler while preserving runtime-specific installation and auditing behavior.
