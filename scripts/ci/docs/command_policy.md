# KUBAPP CI — Command Policy and Validation

## Overview

`command_policy.py` provides policy-based validation for developer-defined commands before they are executed through the component execution boundary.

Its primary entry point is:

```python
ensure_command_is_safe(command, runtime=None)
```

The function validates the command structure, loads the configured policy, and checks the executable, command arguments, shell operators, and runtime-specific restrictions.

The policy is loaded from `command_policy.json`, located alongside `command_policy.py`.

The module raises `UnsafeCommandError` when a command violates its validation rules.

**Security boundary:** This module performs command-policy checks. It does not execute commands, create containers, or independently provide process isolation, filesystem isolation, network restrictions, or resource limits.

---

## 1. Policy File Loading

### `load_policy()`

Loads the policy from:

```text
scripts/ci/command_policy.json
```

The path is determined relative to the location of `command_policy.py`.

The function:
1. Checks whether the policy file exists.
2. Opens the file using UTF-8 encoding.
3. Parses the contents as JSON.
4. Requires the top-level JSON value to be an object, represented in Python by a dictionary.

If the file is missing or the top-level value is not a dictionary, the function raises `RuntimeError`.

JSON parsing errors are not explicitly caught by this function and therefore propagate to the caller.

### Operational implications

The policy file is a required dependency for command validation. If it is unavailable or malformed, the command should not be treated as having passed policy validation.

However, the module does not independently verify that every policy field has the expected type or structure. Individual checks consume selected fields from the loaded dictionary.

---

## 2. Command Structure Validation

### `validate_command(command)`

Requires the command to be a nonempty list of strings.

For example, a command should be represented in argument-list form:

```python
["python", "-m", "pytest"]
```

The validator rejects commands when:
- The command is not a list.
- The list is empty.
- Any argument is not a string.
- The executable argument is empty or contains only whitespace.

Rejected commands raise `UnsafeCommandError`.

### Why argument lists matter

The expected representation separates the executable and its arguments instead of accepting a complete command line as one string.

This helps avoid treating a command string as a shell expression by default. Actual execution behavior still depends on the downstream execution implementation.

**Important limitation:** The validator does not reject every potentially dangerous argument or every possible command construction. It checks the conditions explicitly implemented in this module and the rules present in the policy file.

---

## 3. Executable Normalization

### `normalize_executable(executable)`

Normalizes an executable name before policy comparison.

The function:
1. Removes leading and trailing whitespace.
2. Rejects an empty executable.
3. Extracts the basename when the supplied executable is an absolute path or contains `/`.
4. Uses `shutil.which()` to look up the executable.
5. If the lookup succeeds, uses the basename of the resolved executable path.
6. Converts the resulting name to lowercase.

For example, a resolved executable path can be reduced to its executable name before comparison with the blocked list.

### Limitation

Normalization supports comparisons against executable names, including common path-based invocations. It does not prove that an executable is trustworthy.

The function does not verify executable ownership, file integrity, signatures, or whether the executable can be replaced between validation and execution.

The `shutil.which()` lookup also depends on the environment's executable search path.

---

## 4. Blocked Executables

### `check_executable(command, policy)`

Reads the `executables` list from the policy and compares it with the normalized executable name.

Policy entries are converted to lowercase before comparison.

If the executable appears in the blocked set, the function raises `UnsafeCommandError`.

The policy structure is expected to include an entry similar to:

```json
{
  "executables": []
}
```

The example is illustrative; the actual restrictions depend on the deployed policy file.

### Scope

This check blocks executable names explicitly listed in the policy.

It is not an allowlist. The function does not require every executable to appear in an approved list, and it does not establish that unblocked executables are safe.

---

## 5. Shell-Operator Checks

### `check_operators(command, policy)`

Reads the `operators` list from the policy and searches every command argument for each configured operator.

If an operator occurs anywhere in an argument, the function raises `UnsafeCommandError`.

For example, a policy may choose to block shell operators associated with command chaining or redirection.

The exact restrictions are determined by `command_policy.json`.

### Important limitation

This is a substring-based check, not a complete shell parser.

It does not determine whether an operator would actually be interpreted as shell syntax in a particular context. It may also reject an argument containing an operator character even when that character is ordinary data.

Conversely, the absence of a configured operator does not establish that a command is safe.

Because commands are passed as argument lists, shell operators are not automatically interpreted as shell syntax merely because they appear in an argument. Their significance depends on the executable and its behavior.

---

## 6. Runtime-Specific Argument Restrictions

### `check_runtime_rules(command, runtime, policy)`

Applies configured argument restrictions for the selected runtime.

The function:
1. Returns without checking runtime rules if the runtime is empty.
2. Looks up the runtime in the `runtime_rules` mapping.
3. Reads its `blocked_arguments` list.
4. Compares each command argument, excluding the executable, against the blocked arguments.
5. Raises `UnsafeCommandError` if an argument matches.

Comparisons are case-insensitive and require an exact argument match.

For example, a policy could configure a runtime-specific rule in this general form:

```json
{
  "runtime_rules": {
    "python": {
      "blocked_arguments": []
    }
  }
}
```

This example illustrates the structure only; it does not specify KUBAPP's actual blocked arguments.

### Scope

The check matches individual arguments. It does not parse complex argument syntax, interpret every runtime option, or establish what a command will do after it starts.

Runtime restrictions are only as comprehensive as the configured rules and the checks implemented here.

---

## 7. Blocked File Extensions

### `check_blocked_file_extensions(command, runtime, policy)`

Checks whether a command directly invokes the selected runtime with an argument ending in a configured blocked file extension.

The function:
1. Retrieves the runtime's policy.
2. Reads `blocked_file_extensions`.
3. Normalizes the command executable.
4. Continues only when the normalized executable matches the runtime name.
5. Examines each argument after the executable.
6. Rejects arguments whose lowercase form ends with a configured blocked extension.

A rejection raises `UnsafeCommandError`.

Illustrative policy structure:

```json
{
  "runtime_rules": {
    "python": {
      "blocked_file_extensions": []
    }
  }
}
```

The actual extension restrictions depend on the policy file.

### Scope and limitations

This check targets direct runtime invocation where the executable name matches the runtime.

It does not comprehensively detect:
- Indirect execution through another program.
- Dynamically constructed script paths.
- Content executed from standard input.
- All equivalent ways of passing code to an interpreter.
- Every executable that can launch scripts or other processes.

A blocked-extension check should therefore be treated as one policy control, not a complete restriction on code execution.

---

## 8. Main Validation Entry Point

### `ensure_command_is_safe(command, runtime=None)`

This function coordinates the command-policy checks.

The validation sequence is:

1. Require a nonempty string runtime.
2. Normalize the runtime to lowercase and remove surrounding whitespace.
3. Load the policy file.
4. Validate the command's structure.
5. Check the executable against blocked executables.
6. Check arguments for configured shell operators.
7. Apply runtime-specific blocked-argument rules.
8. Apply runtime-specific blocked-file-extension rules.
9. Return the original command list if all checks pass.

The order matters: the function stops at the first raised exception, so a rejected command may not reach every subsequent check.

### Runtime requirement

The runtime must be a string containing non-whitespace characters. The function raises `UnsafeCommandError` if the runtime is missing, is not a string, or is empty after normalization.

### Return value

On success, the function returns the original command list. It does not execute the command or transform it into a different command representation.

### Error handling

| Condition | Error behavior |
|---|---|
| Missing or invalid runtime | `UnsafeCommandError` |
| Command is not a list | `UnsafeCommandError` |
| Empty command | `UnsafeCommandError` |
| Non-string argument | `UnsafeCommandError` |
| Empty executable | `UnsafeCommandError` |
| Blocked executable | `UnsafeCommandError` |
| Configured operator found | `UnsafeCommandError` |
| Blocked runtime argument | `UnsafeCommandError` |
| Blocked direct script-file extension | `UnsafeCommandError` |
| Missing policy file | `RuntimeError` |
| Policy JSON is not an object | `RuntimeError` |
| Malformed JSON | JSON parsing exception propagates |

---

## 9. Integration with KUBAPP CI

The shared utility `run_extra_checks()` calls `ensure_command_is_safe()` before delegating execution to `run_component_command()`.

Conceptually, the flow is:

```text
Developer-defined extra check
            |
            v
ensure_command_is_safe()
            |
            +---- Rejected ----> Exception propagates
            |
            v
run_component_command()
            |
            v
ComponentEnvironment.run()
```

The policy module and the component execution environment serve different purposes:

- **Command policy:** Rejects commands that violate configured validation rules.
- **Component execution environment:** Provides the execution mechanism and any isolation controls it implements.
- **Orchestration:** Handles resulting exceptions and determines the CI outcome.

Passing command-policy checks does not mean the command is harmless. It means the command passed the checks implemented by the current policy.

---

## 10. Security Considerations

### Policy validation is not execution isolation

The module does not create a container or otherwise isolate a process. Any containment guarantees must come from the execution environment and its configuration.

### Blocking selected executables is not an allowlist

The current implementation rejects executables explicitly listed in the policy. It does not require every command to use a predefined approved executable.

### Operator checks are syntactic

The implementation searches for configured substrings in arguments. It does not parse commands according to shell grammar or fully understand the behavior of individual programs.

### Runtime rules are configuration-dependent

A runtime receives additional restrictions only when a matching rule exists in `runtime_rules`. Missing runtime rules result in no runtime-specific restriction from these checks.

### Policy structure is not fully validated

The policy loader checks the top-level JSON type, but the module does not comprehensively validate the types and contents of every nested field. Invalid policy structures may cause other exceptions during validation.

### Validation and execution are separate operations

The executable is checked before the downstream environment runs the command. This module does not independently bind the validated executable to an immutable file or eliminate possible changes to the execution environment between validation and use.

### Policy checks do not replace other controls

Command validation should be considered alongside:
- Component execution isolation.
- Filesystem and working-directory restrictions.
- Environment-variable and secret handling.
- Network and resource restrictions.
- Dependency and artifact security checks.
- Appropriate execution permissions.

---

## 11. Function Reference

| Function | Responsibility |
|---|---|
| `load_policy()` | Load and validate the policy file's top-level JSON structure. |
| `validate_command()` | Check the command's list structure and string arguments. |
| `normalize_executable()` | Normalize the executable name for policy comparisons. |
| `check_executable()` | Reject executables listed in the blocked set. |
| `check_operators()` | Reject arguments containing configured operator substrings. |
| `check_runtime_rules()` | Reject exact arguments listed for a runtime. |
| `check_blocked_file_extensions()` | Reject configured file extensions in direct runtime invocations. |
| `ensure_command_is_safe()` | Apply the checks and return the command if validation succeeds. |

---

## Summary

`command_policy.py` is a validation layer for developer-defined commands in KUBAPP CI. It enforces configured restrictions on executable names, argument contents, runtime-specific arguments, and selected script-file extensions.

