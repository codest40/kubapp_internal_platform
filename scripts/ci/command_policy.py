import json
import os
import shutil
from pathlib import Path


POLICY_FILE = Path(__file__).with_name("command_policy.json")

class UnsafeCommandError(RuntimeError):
    pass

def load_policy():
    if not POLICY_FILE.exists():
        raise RuntimeError(
            f"Command policy file not found: {POLICY_FILE}"
        )

    with POLICY_FILE.open("r", encoding="utf-8") as file:
        policy = json.load(file)

    if not isinstance(policy, dict):
        raise RuntimeError("Command policy must be a JSON object")

    return policy


def validate_command(command):
    if not isinstance(command, list):
        raise UnsafeCommandError(
            "Command must be provided as a list"
        )

    if not command:
        raise UnsafeCommandError(
            "Command cannot be empty"
        )

    if not all(isinstance(item, str) for item in command):
        raise UnsafeCommandError(
            "Every command argument must be a string"
        )

    if not command[0].strip():
        raise UnsafeCommandError(
            "Command executable cannot be empty"
        )


def normalize_executable(executable):
    executable = executable.strip()

    if not executable:
        raise UnsafeCommandError(
            "Command executable cannot be empty"
        )

    path = Path(executable)

    if path.is_absolute() or "/" in executable:
        name = path.name
    else:
        name = executable

    resolved = shutil.which(executable)

    if resolved:
        name = Path(resolved).name

    return name.lower()


def check_executable(command, policy):
    executable = normalize_executable(command[0])

    blocked = {
        item.lower()
        for item in policy.get("executables", [])
    }

    if executable in blocked:
        raise UnsafeCommandError(
            f"Blocked executable: {executable}"
        )


def check_operators(command, policy):
    operators = policy.get("operators", [])

    for argument in command:
        for operator in operators:
            if operator in argument:
                raise UnsafeCommandError(
                    f"Blocked shell operator '{operator}' "
                    f"found in argument: {argument}"
                )

def check_blocked_file_extensions(
    command,
    runtime,
    policy,
):
    rules = policy.get(
        "runtime_rules",
        {},
    )

    runtime_rule = rules.get(
        runtime.lower(),
    )

    if not runtime_rule:
        return

    blocked_extensions = (
        runtime_rule.get(
            "blocked_file_extensions",
            [],
        )
    )

    executable = normalize_executable(
        command[0],
    )

    if executable != runtime.lower():
        return

    for argument in command[1:]:
        argument_lower = argument.lower()

        for extension in blocked_extensions:
            if argument_lower.endswith(
                extension.lower()
            ):
                raise UnsafeCommandError(
                    f"Blocked direct execution of "
                    f"{extension} file: {argument}"
                )

def check_runtime_rules(command, runtime, policy):
    if not runtime:
        return

    rules = policy.get("runtime_rules", {})
    runtime_rule = rules.get(runtime.lower())

    if not runtime_rule:
        return

    blocked_arguments = {
        item.lower()
        for item in runtime_rule.get("blocked_arguments", [])
    }

    for argument in command[1:]:
        if argument.lower() in blocked_arguments:
            raise UnsafeCommandError(
                f"Blocked {runtime} argument: {argument}"
            )


def ensure_command_is_safe(command, runtime=None):
    if not runtime or not isinstance(runtime, str):
        raise UnsafeCommandError(
          "Runtime must be a non-empty string"
        )
    runtime = runtime.strip().lower()
    policy = load_policy()
    validate_command(command)
    check_executable(command, policy)
    check_operators(command, policy)
    check_runtime_rules(command, runtime, policy)
    check_blocked_file_extensions(command, runtime, policy,)
    return command
