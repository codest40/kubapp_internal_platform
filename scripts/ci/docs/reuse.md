# KUBAPP CI — Shared Utilities

## Overview

`reuse.py` provides shared utilities used by KUBAPP's CI implementation. It centralizes Git metadata retrieval, timestamps, repository-root discovery, logging, timing, command execution, developer-defined checks, and safe file-content collection.

The module also distinguishes between two command-execution paths:

- **Platform commands:** `run_platform_command()` executes trusted platform operations directly through Python's `subprocess` interface.
- **Component commands:** `run_component_command()` delegates execution to a `ComponentEnvironment`, establishing the execution boundary used for component-controlled commands.

Developer-defined extra checks are routed through the component execution path rather than being executed directly by the utility module.

---

## 1. Git Metadata and Repository Discovery

### `get_latest_commit_id()`

Retrieves the current Git commit identifier using:

```bash
git rev-parse HEAD
```

**Behavior:**
- Returns the first 10 characters of the commit hash when the command succeeds.
- Returns a short, randomly generated UUID-based identifier when Git cannot resolve the current commit.

The fallback is not a commit hash. Consumers should treat it as a generated identifier rather than evidence of a specific source revision.

### `get_root(arg=None)`

Retrieves the root directory of the current Git working tree using:

```bash
git rev-parse --show-toplevel
```

**Behavior:**
- Returns the repository-root path as a string by default.
- Returns a `pathlib.Path` object when called with `arg="path"`.
- Returns `False` if Git cannot determine the working-tree root.

Callers must account for the `False` return value before using the result as a filesystem path.

This function discovers the Git working-tree root; it does not independently verify that the repository is the intended KUBAPP checkout.

---

## 2. Timestamps and Timing

### `get_timestamp()`

Returns the current local date and time in this format:

```text
YYYY-MM-DD-HH-MM-SS
```

Example:

```text
2026-10-27-14-30-45
```

The function uses the machine's local clock and does not include a timezone or subsecond precision. Calls made within the same second can therefore return the same value.

### `start_timer()`

Returns a value from `time.perf_counter()`, suitable for measuring elapsed time.

Example:

```python
start = start_timer()

# Operation being measured

elapsed = time.perf_counter() - start
```

The returned value is a timer reading, not a calendar timestamp.

---

## 3. Logging and Formatting

### `BIG_LINE(arg=None)`

Prints the supplied character 80 times. If no argument is provided, it uses `-`.

This helper prints directly to standard output.

### `line_logger(char="=", length=30)`

Returns a separator string containing the specified character repeated for the requested length.

Validation requires:
- `char` to be a nonempty string after whitespace checking.
- `length` to be a positive integer.
- `length` not to be a Boolean value.

The function returns the separator; it does not print it automatically.

### `ci_log(message, level="INFO")`

Prints a message with a level-specific symbol.

Recognized levels are:

| Level | Symbol |
|---|---|
| `INFO` | ℹ️ |
| `SUCCESS` | ✅ |
| `WARNING` | ⚠️ |
| `ERROR` | ❌ |
| `DEBUG` | 🔍 |

The level is converted to uppercase before lookup. Unknown levels use the default informational symbol.

This is console logging, not a structured logging system. The function does not independently persist logs or attach timestamps.

### `_print_result(result)`

Prints a subprocess-like result's captured standard output and standard error when either contains data.

Output is written directly to standard output, with the original captured text preserved.

---

## 4. Trusted Platform Command Execution

### `run_platform_command(command, cwd=None, label=None, env=None)`

Executes a command using Python's `subprocess.run()`.

The function configures execution with:

- `check=True`
- `capture_output=True`
- `text=True`
- Optional working directory through `cwd`
- Optional environment mapping through `env`

On success, captured output is printed and the completed process result is returned.

If the command exits unsuccessfully, the function:
1. Logs an error containing the supplied label or the default `Platform command`.
2. Includes the exit code.
3. Prints captured standard output and standard error when present.
4. Re-raises the `subprocess.CalledProcessError`.

**Trust boundary:** This function does not create a container, apply resource limits, or independently restrict which commands may execute. Its safety depends on the caller supplying trusted platform operations and appropriate arguments and environment settings.

It should not be treated as a safe execution interface for arbitrary developer-controlled commands.

---

## 5. Component Command Execution

### `run_component_command(command, component_environment, cwd=None, label=None, timeout_seconds=None)`

Delegates command execution to a supplied `ComponentEnvironment`.

Before execution, the function verifies that `component_environment` is an instance of `ComponentEnvironment`. An invalid object raises `TypeError`.

It then calls the environment's `run()` method with:

- `command`
- `cwd`
- A supplied label, or `Component command` by default
- `timeout_seconds`

On success, captured output is printed and the result is returned.

If a `ComponentEnvironmentError` is raised, the function logs the failure and re-raises the exception.

**Trust boundary:** Unlike `run_platform_command()`, this function delegates execution to the component execution environment. The actual isolation and enforcement properties depend on the implementation and configuration of `ComponentEnvironment`; this wrapper alone does not prove that commands are sandboxed.

The function also does not independently impose a timeout when `timeout_seconds` is omitted. Any default timeout behavior must come from the execution environment.

---

## 6. Developer-Defined Extra Checks

### `run_extra_checks(extra_ci_config, runtime, app_name, app_dir, component_environment)`

Runs developer-defined checks using the component execution boundary.

For each entry in `extra_ci_config`, the function:

1. Logs the check name.
2. Passes the configured command and runtime to `ensure_command_is_safe()`.
3. Executes the resulting command through `run_component_command()`.
4. Logs a success message if execution completes without raising an exception.

The command is executed with `app_dir` as the requested working directory.

If command validation or execution raises an exception, the function does not mark that check as successful and does not suppress the exception.

### Important distinctions

- `ensure_command_is_safe()` performs the command-policy validation requested by this function.
- `ComponentEnvironment` is responsible for the execution behavior delegated to it.
- `run_extra_checks()` coordinates these operations; it does not implement the policy or isolation mechanisms itself.
- The function expects `extra_ci_config` to provide an `.items()` interface. It does not independently validate that the input is a dictionary.
- The function does not itself implement dependency vulnerability scanning. Such checks require separate configured commands or other CI functionality.

---

## 7. Safe File-Content Collection

### `collect_content(file_path, allowed_root=None)`

Reads a regular file as UTF-8 text without executing its contents.

The function validates that:
- `file_path` is a nonempty string or `Path`.
- If supplied, `allowed_root` is a string or `Path`.
- The resolved file path remains inside the resolved allowed root when that restriction is enabled.
- The target exists and is a regular file.
- The file can be read as UTF-8 text.

When `allowed_root` is supplied, the containment check uses resolved filesystem paths and rejects paths that resolve outside the permitted directory.

**Return value:** The file's text content as a string.

### Error handling

The function raises:
- `TypeError` for invalid argument types.
- `ValueError` for an empty file path or a path outside the permitted root.
- `FileNotFoundError` if the target does not exist or is not a regular file.
- `RuntimeError` if reading the file fails with an `OSError` or `UnicodeError`.

### Security considerations

`collect_content()` does not execute the file. It also does not establish that the file's contents are trustworthy, safe to interpret, or free from secrets.

The allowed-root check is a path-containment check; it should not be mistaken for a complete defense against every filesystem race condition or symlink-related threat.

---

## 8. Error-Handling Summary

| Function | Main failure behavior |
|---|---|
| `get_latest_commit_id()` | Returns a generated fallback identifier if Git fails. |
| `get_root()` | Returns `False` if Git cannot determine the repository root. |
| `line_logger()` | Raises `ValueError` for invalid arguments. |
| `run_platform_command()` | Logs command failure and re-raises `CalledProcessError`. |
| `run_component_command()` | Raises `TypeError` for an invalid environment and logs/re-raises `ComponentEnvironmentError`. |
| `run_extra_checks()` | Propagates command-policy and execution errors. |
| `collect_content()` | Raises an exception appropriate to the argument, containment, file, or read failure. |

---

## 9. Security and Operational Boundaries

`reuse.py` provides common interfaces; it does not, by itself, establish the complete security posture of KUBAPP CI.

Important boundaries include:

1. **Trusted versus component-controlled commands:** Platform operations and developer-defined commands use separate execution functions.
2. **Delegated isolation:** Component command isolation depends on `ComponentEnvironment` and its underlying implementation.
3. **Command-policy validation:** Extra checks are passed through `ensure_command_is_safe()`, but command validation and execution isolation are separate controls.
4. **Filesystem containment:** `collect_content()` can restrict reads to a resolved directory boundary when `allowed_root` is provided.
5. **Output handling:** Captured command output is printed to standard output. Callers should consider whether commands could emit secrets or other sensitive information.
6. **Failure propagation:** Execution and file-reading errors are generally raised to callers, allowing the orchestration layer to decide how to handle failures.

The actual security guarantees must be assessed alongside `command_policy.py`, `component_execution_env.py`, and the callers of these utilities.

---

## 10. Function Reference

| Function | Responsibility |
|---|---|
| `get_latest_commit_id()` | Retrieve a short Git commit identifier, with a generated fallback. |
| `get_timestamp()` | Generate a local timestamp string. |
| `get_root()` | Resolve the Git working-tree root. |
| `start_timer()` | Obtain a monotonic timer reading. |
| `BIG_LINE()` | Print a repeated-character separator. |
| `line_logger()` | Return a repeated-character separator. |
| `ci_log()` | Print a message with a level-specific symbol. |
| `_print_result()` | Print captured standard output and standard error. |
| `run_platform_command()` | Execute trusted platform commands. |
| `run_component_command()` | Delegate command execution to `ComponentEnvironment`. |
| `run_extra_checks()` | Validate and execute developer-defined extra checks. |
| `collect_content()` | Read UTF-8 file contents, optionally enforcing path containment. |
