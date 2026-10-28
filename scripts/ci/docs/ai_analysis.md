# KUBAPP CI — AI Artifact Assessment

## Overview

`ai_analysis.py` implements the AI assessment layer used by KUBAPP CI to assess artifacts before they are executed or used.

It loads the security rules associated with an artifact type, sends the execution context and rules to the AI assessment entry point, validates the response, and returns a normalized assessment result for the decision-enforcement layer.

The module exposes one primary function:

- `analyze_data(args)` — validates the assessment context, loads the applicable ruleset, coordinates the assessment request, validates the response, and returns the result.

The module does not itself execute the assessed artifact or persist the final assessment report. Those responsibilities belong to other parts of the CI workflow.

## Supported Artifact Types

The module maps artifact types to JSON rules files under `scripts/ci/ai/rules/`.

| Artifact type | Rules file |
|---|---|
| `command` | `commands.json` |
| `script` | `scripts.json` |
| `module` | `modules.json` |
| `dockerfile` | `dockerfile.json` |

The requested artifact type must match one of the keys in `RULE_FILES`.

The corresponding rules file must exist and contain valid JSON. The ruleset must also provide:

- `ruleset_id` — a non-empty string identifying the ruleset.
- `ruleset_version` — a non-empty string identifying the ruleset version.
- `artifact_type` — a value matching the requested artifact type.

Missing files, invalid JSON, missing ruleset identifiers, or a mismatched artifact type cause the assessment to fail before the AI entry point is called.

## Assessment Context

`analyze_data(args)` expects a non-empty dictionary representing the execution context.

The context is passed to the assessment entry point alongside the selected rules:

```python
request = {
    "context": args,
    "rules": rules,
}
```

The context may contain information such as the application name, artifact type, component directory, runtime, command details, or script content, depending on the caller.

The function validates that the context is a non-empty dictionary and that its `artifact_type` is supported. It does not independently validate every field that a particular artifact type might require; that responsibility depends on the caller and the rules used by the assessment system.

## Assessment Execution and Concurrency

The assessment is performed through:

`mcp_entry(request)`

The call is protected by the module-level `AI_ASSESSMENT_LOCK`, a Python threading lock.

This means calls using this lock are serialized within the same Python process. If multiple threads attempt an assessment, only one can execute the protected assessment call at a time.

The lock does **not** coordinate assessments across separate processes, CI runners, or machines. It should not be interpreted as a distributed lock.

The function logs when an assessment begins and completes, including the application name.

If the assessment call raises an exception, the module wraps it in a `RuntimeError` indicating that the relevant artifact must not proceed. The original exception is retained as the cause.

This provides a fail-closed response to assessment-call failures, provided the caller does not suppress the exception and continue execution.

## Assessment Response Validation

After `mcp_entry()` returns, the module validates the response before returning it to the caller.

The response must be a dictionary containing the following fields:

| Field | Validation requirement |
|---|---|
| `decision` | Integer `0` or `1`; booleans are rejected. |
| `reason` | Non-empty string. |
| `evidence` | List containing only non-empty strings. |
| `recommendations` | List of recommendation dictionaries. |

Each recommendation must contain:

| Field | Validation requirement |
|---|---|
| `priority` | One of `low`, `medium`, or `high`. |
| `action` | Non-empty string. |
| `rationale` | Non-empty string. |

If the returned result does not satisfy the expected structure, the function raises a `RuntimeError`.

This validation establishes that the response has the expected shape. It does not independently verify the factual accuracy of the evidence, the quality of the recommendations, or the reasoning behind the decision.

## Normalized Assessment Result

After validation, `analyze_data()` returns a dictionary with a consistent structure:

| Field | Source |
|---|---|
| `ruleset_id` | Loaded rules file. |
| `ruleset_version` | Loaded rules file. |
| `artifact_type` | Validated execution context. |
| `app_name` | Execution context, defaulting to `"unknown"` when absent. |
| `decision` | Validated assessment response. |
| `reason` | Validated assessment response. |
| `evidence` | Validated assessment response. |
| `recommendations` | Validated assessment response. |

The ruleset metadata is taken from the locally loaded rules file rather than from the AI response. This allows the downstream decision layer to record which configured ruleset was supplied for the assessment.

The function does not return the entire raw response from `mcp_entry()`. Instead, it returns the fields required by the downstream decision-enforcement component.

## Integration with Decision Enforcement

`analyze_data()` is the assessment stage; `KUBAPP_DECISION()` is the subsequent enforcement and reporting stage.

The intended flow is:

1. The caller constructs the artifact execution context.
2. `analyze_data()` validates the context and loads the applicable rules.
3. The module calls `mcp_entry()` with the context and rules.
4. The returned response is validated and normalized.
5. The caller passes the result to `KUBAPP_DECISION()`.
6. `KUBAPP_DECISION()` records the assessment report and enforces the decision.
7. A rejected assessment raises an exception rather than returning normally.

In simplified form:

```text
Artifact execution context
          |
          v
Validate context and artifact type
          |
          v
Load artifact-specific rules
          |
          v
Call mcp_entry(context + rules)
          |
          v
Validate assessment response
          |
          v
Return normalized result
          |
          v
KUBAPP_DECISION(result)
          |
          +---- decision = 0 ----> Continue caller's workflow
          |
          +---- decision = 1 ----> Reject and raise exception
```

The exact point at which the caller invokes these functions matters. The assessment must complete, and its decision must be enforced, before the assessed artifact is executed or used.

## Failure Handling

The module fails rather than returning a normal assessment result in the following situations:

- The context is not a dictionary or is empty.
- The artifact type is unsupported.
- The required rules file is missing or unreadable.
- The rules file contains invalid JSON.
- Required ruleset metadata is invalid.
- The configured artifact type does not match the requested type.
- `mcp_entry()` raises an exception.
- The assessment response is not a dictionary.
- The decision, reason, evidence, or recommendation structure is invalid.

These failures prevent `analyze_data()` from returning a normalized assessment result.

The function does not itself guarantee that execution stops across the entire CI workflow. That depends on how callers handle exceptions.

## Operational Considerations

### 1. Ruleset integrity matters

The assessment uses the JSON rules file selected from `RULE_FILES`. The function checks required metadata and the artifact-type match, but it does not cryptographically verify the rules file or validate every rule's internal semantics.

The integrity and review process for the rules directory therefore remain important parts of the assessment system.

### 2. The lock is process-local

`AI_ASSESSMENT_LOCK` prevents overlapping calls through this lock within one Python process. It does not serialize assessment requests across multiple CI processes or machines.

### 3. Response validation is structural

A well-formed response is not necessarily a correct response. The function validates the expected fields and allowed values, not whether the assessment reached the right conclusion.

### 4. Assessment failure must remain a blocking failure

The module raises exceptions when the assessment call fails or returns an invalid response. Callers must not catch these exceptions and continue as though the artifact had passed.

### 5. The module does not persist reports

`analyze_data()` returns a normalized result but does not write the final report to disk or commit it to Git. Report persistence and rejection handling are implemented in `platform_decision.py`.

### 6. The assessment backend is an external dependency

The assessment relies on `mcp_entry()` and the components behind it. The behavior and trustworthiness of the backend cannot be established from `ai_analysis.py` alone.

## Scope and Limitations

`ai_analysis.py` is responsible for **selecting assessment rules, coordinating the assessment call, validating the response structure, and returning a normalized result**.

It does not:

- Generate the assessment rules.
- Independently verify that the assessment is factually correct.
- Execute the assessed command or script.
- Persist the final assessment report.
- Enforce the decision independently of its caller.
- Provide distributed locking across CI processes or machines.
- Establish command isolation or sandboxing.

It forms the assessment layer between artifact context and KUBAPP's decision-enforcement workflow.
