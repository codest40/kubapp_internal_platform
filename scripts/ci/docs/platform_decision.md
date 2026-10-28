# KUBAPP CI — AI Assessment Decision and Reporting

## Overview

`platform_decision.py` implements the decision-enforcement and reporting stage for KUBAPP's AI-assisted CI assessments.

It validates assessment results, records each valid assessment as a JSON report, and determines whether the associated command or script may continue based on the assessment decision.

The module exposes two main functions:

- `KUBAPP_DECISION(result)` — validates the assessment, persists its report, and enforces the decision.
- `commit_ai_ci_report()` — stages, commits, and pushes changes to the AI assessment report directory.

The module does not generate the assessment itself. It receives an assessment result from another component and enforces the result according to its defined contract.

## Assessment Result Contract

`KUBAPP_DECISION()` requires a dictionary containing the following fields:

| Field | Requirement | Purpose |
|---|---|---|
| `ruleset_id` | Non-empty string | Identifies the ruleset used for the assessment. |
| `ruleset_version` | Non-empty string | Identifies the ruleset version. |
| `decision` | Integer `0` or `1` | Determines whether the assessment passes or rejects the artifact. |
| `reason` | Non-empty string | Explains the decision. |
| `evidence` | List of non-empty strings | Records the evidence supporting the assessment. |
| `recommendations` | List of dictionaries | Contains advisory recommendations. |

Each recommendation must contain:

| Field | Requirement |
|---|---|
| `priority` | One of `low`, `medium`, or `high`. |
| `action` | Non-empty string describing the recommended action. |
| `rationale` | Non-empty string explaining the recommendation. |

The optional `artifact_type` and `app_name` fields default to `"unknown"` when absent. Their values are converted to strings when the report is constructed.

The function validates the required fields and recommendation structure before creating a report. Invalid results raise an exception rather than proceeding as a successful assessment.

## Decision Semantics

The module defines two decision values:

| Decision | Meaning | Outcome |
|---|---|---|
| `0` | No security concern requiring rejection was identified. | The report is persisted, and the function returns the report. |
| `1` | A security concern requiring rejection was identified. | The report is persisted, a report-commit attempt is made, and the function raises an exception. |

Recommendations are advisory. Their priorities do not override or determine the decision.

A recommendation marked `high` does not independently reject an artifact. Conversely, a decision of `0` is accepted even when recommendations are present.

**Important:** A passing decision means the supplied assessment result passed this enforcement function. It does not independently establish that the assessment was accurate, that the ruleset was trustworthy, or that the artifact is safe in every respect.

## Assessment Report Generation

For each valid result, `KUBAPP_DECISION()` creates a report containing:

- `assessment_id` — a newly generated UUID.
- `assessed_at` — the assessment timestamp in UTC, formatted as an ISO 8601 string.
- `app_name` — the application name, converted to a string.
- `artifact_type` — the artifact type, converted to a string.
- `ruleset_id` and `ruleset_version`.
- `decision` and `reason`.
- `evidence`.
- `recommendations`.

The report filename is constructed from a sanitized application name and the assessment UUID:

`<safe_app_name>_<assessment_id>.json`

Characters outside letters, digits, underscores, periods, and hyphens are replaced with underscores. Leading and trailing underscores, periods, and hyphens are stripped. If the result is empty, the name becomes `unknown`.

The unique assessment ID allows multiple reports for the same application to be stored without deliberately reusing the same filename.

## Report Storage

Reports are written under:

`gitops/state/ai_ci_report/`

The directory is resolved relative to the repository root calculated from the module's location.

The report-writing sequence is:

1. Create the report directory if necessary.
2. Create a temporary file inside that directory.
3. Serialize the report as indented JSON.
4. Append a newline.
5. Replace the destination path with the temporary file using `os.replace()`.

Using a temporary file in the destination directory and replacing the destination helps avoid exposing a partially written final report.

If report persistence fails with a handled filesystem, serialization, or value error, the function attempts to remove the temporary file and raises a `RuntimeError` stating that the command or script must not execute.

**Fail-closed behavior:** A report-persistence failure prevents the function from returning a successful decision. Callers must allow the exception to stop the relevant execution path for this guarantee to hold.

## Rejection Report Commit and Push

When `decision == 1`, the function calls `commit_ai_ci_report()` before raising the rejection exception.

The commit function:

1. Configures the local Git author as `github-actions`.
2. Configures the author email as `github-actions@github.com`.
3. Stages changes under `gitops/state/ai_ci_report/`.
4. Checks whether that path has staged changes.
5. If changes exist, creates a commit with the message:

   `[KUBAPP AI] Record rejected assessment report`

6. Pushes the current `HEAD` to `origin`, targeting `main`.

If there are no staged changes under the report directory, the function logs that there are no report changes to commit and returns without creating a commit.

The commit operation scopes its `git add`, staged-change check, and commit to the report directory. However, the push command pushes `HEAD` to `main`; it does not explicitly restrict the push to the report files.

### Commit Failure Handling

The rejection path catches `OSError` and `subprocess.CalledProcessError` raised during the commit-and-push attempt. It logs a warning and continues to reject the artifact.

Therefore:

- A rejection does not depend on the report being successfully pushed.
- A Git failure does not convert a rejection into a passing decision.
- A report may exist locally without being committed or pushed.
- Other exception types from the commit operation are not caught by this specific handler.

The report is persisted before the Git operation begins, so a Git failure does not ordinarily undo the local report.

## Execution Flow

The overall sequence is:

1. Receive the assessment result.
2. Validate the result and its recommendations.
3. Generate an assessment ID and UTC timestamp.
4. Construct the report.
5. Persist the report to `gitops/state/ai_ci_report/`.
6. Print the ruleset, artifact type, decision, reason, recommendation count, and report path.
7. If the decision is `1`, attempt to commit and push the report, then raise a rejection exception.
8. If the decision is `0`, log that the assessment passed and return the report.

In simplified form:

```text
Assessment result
       |
       v
Validate result structure
       |
       v
Construct assessment report
       |
       v
Persist JSON report
       |
       v
Evaluate decision
       |
       +---- decision = 0 ----> Return report
       |
       +---- decision = 1 ----> Attempt report commit/push
                                      |
                                      v
                               Raise rejection error
```

## Integration with CI Command Execution

The decision function is intended to be called before the relevant command or script executes.

When the function receives a rejection decision, it raises a `RuntimeError` rather than returning a report normally. In the documented `run_ci.py` flow, this exception occurs before the subsequent component-command execution call.

This creates an enforcement boundary between the AI assessment result and execution of the assessed artifact.

The guarantee depends on the caller invoking `KUBAPP_DECISION()` at the correct point and not catching or suppressing the rejection exception in a way that permits execution to continue.

## Operational Considerations

### 1. The report is not a substitute for the assessment

This module validates the result's structure, not the correctness of its evidence or the trustworthiness of the ruleset that produced it.

### 2. Recommendations do not enforce controls

Recommendations are recorded for review. The function does not automatically implement them or use their priority to determine whether to reject an artifact.

### 3. Git credentials and permissions are external dependencies

Successful report publication depends on the Git environment, repository state, remote configuration, and credentials available to the executing process. The code configures the author identity but does not configure authentication or grant repository permissions.

### 4. The commit operation can include previously staged changes

The function stages only the report directory and scopes its staged-change check to that directory. However, `git commit` is not given an explicit pathspec or an isolated index, so previously staged changes outside that directory may also be included in the commit.

The push targets `HEAD:main`. This assumes the intended branch and remote state are compatible with that operation; it does not create a dedicated branch for each assessment.

### 5. A rejected report may not reach the remote repository

Git commit or push failures are logged as warnings, after which the function still raises the rejection exception. Local report persistence and remote report publication are separate outcomes.

### 6. Passing decisions are not committed by this function

The report is written locally for both passing and rejected assessments. The explicit Git commit-and-push flow runs only for rejected assessments.

### 7. Report data requires appropriate handling

Reports can contain application names, artifact types, evidence, reasons, and recommendations. Repository access and retention policies should account for the possibility that these fields reveal internal implementation or security findings.

## Scope and Limitations

`platform_decision.py` is responsible for **assessment-result validation, report persistence, and decision enforcement**.

It does not:

- Generate the AI assessment or independently verify the ruleset.
- Execute recommendations.
- Run dependency vulnerability scans.
- Sandbox the assessed command or script.
- Guarantee that a rejected report is successfully published to Git.
- Guarantee that downstream callers terminate execution unless the rejection exception is allowed to propagate.

