# KUBAPP CI — CI Runner and Execution Flow

## Overview

`run_ci.py` defines the `CIRunner` class, which coordinates the CI stages for an application component.

It supports two execution paths:

- **Default CI checks:** Runs the runtime handler's linting, security analysis, and unit tests.
- **Developer CI scripts:** Reads and analyzes configured Python or Bash scripts before executing them through the component execution environment.

Both paths install dependencies first, execute configured extra CI commands when present, and then build the application image from its Dockerfile.

The runner coordinates these stages but delegates runtime-specific operations, command execution, AI analysis, and platform decisions to other modules.

---

## 1. CIRunner Initialization

```python
CIRunner(handler, use_script=False, ci_scripts=None)
```

The constructor stores three values:

| Parameter | Purpose |
|---|---|
| `handler` | Runtime handler responsible for dependency installation, default checks, and Dockerfile builds. |
| `use_script` | Selects developer-defined scripts instead of the default CI checks when `True`. |
| `ci_scripts` | List of developer-defined script paths used when script execution is enabled. |

The handler also provides information used by the runner, including the application name, application directory, runtime, and component execution environment.

The constructor itself does not validate the script paths. Validation occurs when `run_scripts()` executes, with additional application configuration validation handled elsewhere in the CI pipeline.

---

## 2. CI Execution Flow

The `run()` method coordinates the main CI sequence.

```text
CIRunner.run()
       |
       v
Install dependencies
       |
       v
Choose execution path
       |
       +-----------------------------+
       |                             |
       v                             v
Default CI checks             Developer CI scripts
       |                             |
       v                             v
Lint                          Read and analyze scripts
       |                             |
       v                             v
Security analysis             Apply platform decision
       |                             |
       v                             v
Unit tests                    Execute through component
                              execution environment
       |                             |
       +--------------+--------------+
                      |
                      v
             Run extra CI commands
                 if configured
                      |
                      v
             Build from Dockerfile
                      |
                      v
             Return build result
```

This diagram represents the runner's control flow. If a stage raises an exception, subsequent stages are not reached unless that exception is handled by the called operation.

### Execution order

1. Print a message identifying the selected CI execution path.
2. Install dependencies through the runtime handler.
3. Run either developer-defined CI scripts or the default CI checks.
4. Run extra CI commands when configured.
5. Build the image from the Dockerfile.
6. Print the successful completion message and return the build result.

The success message is printed only after `build_from_dockerfile()` returns successfully.

---

## 3. Default CI Checks

When `use_script` is `False`, the runner invokes three handler methods in order:

```python
handler.lint()
handler.security_analysis()
handler.unit_tests()
```

### Linting

Calls the runtime handler's `lint()` method.

The specific tools and checks depend on the handler implementation.

### Security analysis

Calls `handler.security_analysis()`.

The runtime handler determines the security checks performed. The runner itself does not implement dependency auditing or source-code security scanning.

### Unit tests

Calls `handler.unit_tests()`.

The specific test command and behavior depend on the runtime handler.

### Failure behavior

These methods are called sequentially. If an earlier operation raises an exception, later operations in the sequence are not executed.

The runner does not independently decide whether a failed lint, security check, or test should be ignored.

---

## 4. Developer-Defined CI Scripts

When `use_script` is `True`, the runner invokes `run_scripts()` instead of the default lint, security-analysis, and unit-test sequence.

### Script-list validation

The runner requires `ci_scripts` to be a nonempty list.

Each entry must be a nonempty string representing a script path.

Invalid entries raise `RuntimeError`.

### Path resolution and containment

The application root is resolved from:

```python
Path(self.handler.app_dir).resolve()
```

Each configured script path is resolved relative to this application root.

The runner then checks whether the resolved path is relative to the resolved application root. A path that resolves outside the root is rejected.

It also requires the resolved script path to refer to a regular file.

These checks prevent configured script paths from escaping the application directory through ordinary relative-path traversal or paths that resolve outside that directory.

The runner uses `reuse.collect_content()` with `allowed_root=app_root` when reading the script for analysis, applying a second path-containment check to that read operation.

### Supported script types

The runner selects the command according to the file extension:

| Extension | Command representation |
|---|---|
| `.py` | `["python", "<relative-script-path>"]` |
| `.sh` | `["bash", "<relative-script-path>"]` |

Extensions are compared case-insensitively.

Scripts with other extensions are rejected.

The script path passed to the command is relative to the application root, and execution is requested with that root as the working directory.

### Script analysis before execution

For each script, the runner reads its contents and calls `analyze_data()` with a payload containing:

- `app_name`
- `artifact_type`, set to `script`
- `script_content`
- `component_dir`
- `runtime`

The analysis result is passed to:

```python
KUBAPP_DECISION(result)
```

The runner then delegates script execution to:

```python
reuse.run_component_command(
    command,
    component_environment=self.handler.component_environment,
    cwd=app_root,
    label=f"[{self.handler.app_name}] CI script: {script}",
)
```

The script must therefore pass through the analysis and platform-decision calls before execution is attempted.

**Important distinction:** Calling `analyze_data()` and `KUBAPP_DECISION()` does not, by itself, establish what security guarantees the analysis provides or whether execution will be permitted. Those guarantees depend on the implementations of the analysis and decision modules.

Likewise, the runner delegates execution to the component environment rather than directly invoking `subprocess.run()` for the developer script.

### Script failure behavior

If path validation, content collection, analysis, platform-decision handling, or component command execution raises an exception, `run_scripts()` does not catch it locally. The exception propagates to the caller.

Scripts are processed sequentially in the order provided in `ci_scripts`.

---

## 5. Extra CI Commands

After either the default checks or developer scripts finish, the runner checks whether `handler.extra_ci_commands` is truthy.

If so, it calls:

```python
reuse.run_extra_checks(
    handler.extra_ci_commands,
    handler.runtime,
    handler.app_name,
    handler.app_dir,
    component_environment=handler.component_environment,
)
```

This delegates extra-command validation and execution to the shared utilities.

The extra checks are not restricted to the developer-script branch. They can run after either CI path.

If an extra check raises an exception, the runner does not proceed to the Dockerfile build.

---

## 6. Dockerfile Build

After the selected CI checks and any extra commands complete, the runner calls:

```python
handler.build_from_dockerfile()
```

The actual image-building behavior belongs to the runtime handler.

The returned value is stored and returned by `CIRunner.run()`.

The runner does not itself define:
- Dockerfile parsing or validation rules.
- The build engine or image-building implementation.
- Image tagging or registry publication.
- Container health-check behavior.

Those operations are handled elsewhere in the CI pipeline.

---

## 7. Error Propagation

`CIRunner` does not wrap the entire `run()` method in a general exception handler.

Consequently, exceptions raised by dependency installation, default checks, script validation, analysis, extra checks, or image building propagate to the caller.

This makes the runner responsible for coordinating execution order, while higher-level orchestration determines how failures affect the overall CI result.

The runner also does not implement cleanup of the component execution environment in this file. Environment lifecycle and cleanup must be verified in the responsible environment-management code.

---

## 8. Security Boundaries and Limitations

### Script path validation

Configured developer scripts are resolved and checked against the application directory before execution. This is a path-containment control, not a complete filesystem sandbox.

### AI-assisted script analysis

Script contents are passed to `analyze_data()`, and its result is passed to `KUBAPP_DECISION()` before the script is executed.

The runner does not itself define the analysis criteria, decision policy, or enforcement guarantees of those modules.

### Component execution boundary

Developer scripts and extra CI commands are executed through the component execution environment.

The strength of isolation depends on that environment's implementation and configuration. This file alone does not establish CPU, memory, process, filesystem, or network restrictions.

### Sequential script execution

The runner processes developer scripts sequentially within a component. This does not establish whether different components are executed concurrently by the wider CI orchestrator.

### Default checks

The default branch delegates linting, security analysis, and testing to the runtime handler. Their security coverage depends on the tools and configuration used by that handler.

### Build-stage ordering

The Dockerfile build occurs after the selected checks and extra commands. The runner does not itself perform registry publication or container health checks.

---

## 9. Function Reference

| Function | Responsibility |
|---|---|
| `CIRunner.__init__()` | Store the handler and CI execution configuration. |
| `CIRunner.run_scripts()` | Validate, analyze, and execute developer-defined Python or Bash scripts. |
| `CIRunner.run()` | Coordinate dependency installation, CI checks, extra commands, and Dockerfile building. |

---

## Summary

`run_ci.py` is the execution coordinator for a component's CI stages.

It installs dependencies, selects either the default checks or developer-defined scripts, runs configured extra checks, and delegates image building to the runtime handler.

For developer-defined scripts, it also validates script paths, reads their contents for analysis, passes the analysis result to the platform decision function, and delegates execution to the component environment.
The runner's security guarantees depend on the policy, analysis, execution-environment, and runtime-handler implementations it calls.
