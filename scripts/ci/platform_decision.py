import subprocess
import json
import os
import re
import tempfile
import uuid
from datetime import datetime, timezone
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
REPORT_DIR = REPO_ROOT / "gitops" / "state" / "ai_ci_report"
RECOMMENDATION_PRIORITIES = {"low", "medium", "high"}


def commit_ai_ci_report():
    """Commit and push only KUBAPP AI assessment reports."""
    relative_path = REPORT_DIR.relative_to(REPO_ROOT).as_posix()

    subprocess.run(
        ["git", "config", "user.name", "github-actions"],
        cwd=REPO_ROOT,
        check=True,
    )
    subprocess.run(
        ["git", "config", "user.email", "github-actions@github.com"],
        cwd=REPO_ROOT,
        check=True,
    )
    subprocess.run(
        ["git", "add", "--", relative_path],
        cwd=REPO_ROOT,
        check=True,
    )

    staged = subprocess.run(
        ["git", "diff", "--cached", "--quiet", "--", relative_path],
        cwd=REPO_ROOT,
        check=False,
    )

    if staged.returncode == 0:
        print("[KUBAPP AI] No report changes to commit.")
        return

    if staged.returncode != 1:
        raise RuntimeError("Unable to inspect staged AI report changes.")

    subprocess.run(
        [
            "git",
            "commit",
            "-m",
            "[KUBAPP AI] Record rejected assessment report",
            "--",
            relative_path,
        ],
        cwd=REPO_ROOT,
        check=True,
    )
    subprocess.run(
        ["git", "push", "origin", "HEAD:main"],
        cwd=REPO_ROOT,
        check=True,
    )
    print("[KUBAPP AI] Rejection report committed and pushed.")


def KUBAPP_DECISION(result):
    """
    Validate, record, and enforce a KUBAPP AI assessment result.

    Decision semantics:
        0: No security concern requiring rejection was identified.
        1: A security concern requiring rejection was identified.

    Recommendations are advisory and never determine the decision.
    """
    if not isinstance(result, dict):
        raise TypeError(
            "KUBAPP assessment result must be a dictionary."
        )

    ruleset_id = result.get("ruleset_id")
    ruleset_version = result.get("ruleset_version")
    decision = result.get("decision")
    reason = result.get("reason")
    evidence = result.get("evidence")
    recommendations = result.get("recommendations")

    if not isinstance(ruleset_id, str) or not ruleset_id.strip():
        raise RuntimeError(
            "Invalid KUBAPP assessment: ruleset_id is required."
        )

    if (
        not isinstance(ruleset_version, str)
        or not ruleset_version.strip()
    ):
        raise RuntimeError(
            "Invalid KUBAPP assessment: ruleset_version is required."
        )

    if type(decision) is not int or decision not in (0, 1):
        raise RuntimeError(
            "Invalid KUBAPP assessment: decision must be 0 or 1."
        )

    if not isinstance(reason, str) or not reason.strip():
        raise RuntimeError(
            "Invalid KUBAPP assessment: reason is required."
        )

    if (
        not isinstance(evidence, list)
        or not all(
            isinstance(item, str) and item.strip()
            for item in evidence
        )
    ):
        raise RuntimeError(
            "Invalid KUBAPP assessment: evidence must be a list "
            "of non-empty strings."
        )

    if not isinstance(recommendations, list):
        raise RuntimeError(
            "Invalid KUBAPP assessment: recommendations must "
            "be a list."
        )

    for index, recommendation in enumerate(recommendations):
        if not isinstance(recommendation, dict):
            raise RuntimeError(
                "Invalid KUBAPP assessment: recommendation "
                f"{index} must be a dictionary."
            )

        priority = recommendation.get("priority")
        action = recommendation.get("action")
        rationale = recommendation.get("rationale")

        if (
            not isinstance(priority, str)
            or priority not in RECOMMENDATION_PRIORITIES
        ):
            raise RuntimeError(
                "Invalid KUBAPP assessment: recommendation "
                f"{index} has an invalid priority."
            )

        if not isinstance(action, str) or not action.strip():
            raise RuntimeError(
                "Invalid KUBAPP assessment: recommendation "
                f"{index} requires a non-empty action."
            )

        if not isinstance(rationale, str) or not rationale.strip():
            raise RuntimeError(
                "Invalid KUBAPP assessment: recommendation "
                f"{index} requires a non-empty rationale."
            )

    artifact_type = result.get("artifact_type", "unknown")
    app_name = result.get("app_name", "unknown")
    assessment_id = uuid.uuid4().hex
    assessed_at = datetime.now(timezone.utc).isoformat()

    report = {
        "assessment_id": assessment_id,
        "assessed_at": assessed_at,
        "app_name": str(app_name),
        "artifact_type": str(artifact_type),
        "ruleset_id": ruleset_id,
        "ruleset_version": ruleset_version,
        "decision": decision,
        "reason": reason,
        "evidence": evidence,
        "recommendations": recommendations,
    }

    safe_app_name = re.sub(
        r"[^A-Za-z0-9_.-]+", "_", str(app_name)
    ).strip("._-") or "unknown"

    filename = f"{safe_app_name}_{assessment_id}.json"

    try:
        REPORT_DIR.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            dir=REPORT_DIR,
            prefix=".assessment-",
            suffix=".tmp",
            delete=False,
        ) as report_file:
            temporary_path = Path(report_file.name)
            json.dump(report, report_file, indent=2)
            report_file.write("\n")

        os.replace(
            temporary_path,
            REPORT_DIR / filename,
        )
    except (OSError, TypeError, ValueError) as exc:
        try:
            if "temporary_path" in locals():
                temporary_path.unlink(missing_ok=True)
        except OSError:
            pass

        raise RuntimeError(
            "Failed to persist the KUBAPP assessment report. "
            "The command or script must not execute."
        ) from exc

    print(
        f"[KUBAPP AI] Ruleset: {ruleset_id}@{ruleset_version}"
    )
    print(f"[KUBAPP AI] Artifact type: {artifact_type}")
    print(f"[KUBAPP AI] Decision: {decision}")
    print(f"[KUBAPP AI] Reason: {reason}")
    print(
        f"[KUBAPP AI] Recommendations: {len(recommendations)}"
    )
    print(f"[KUBAPP AI] Report: {REPORT_DIR / filename}")

    if decision == 1:
        try:
            commit_ai_ci_report()
        except (OSError, subprocess.CalledProcessError) as exc:
            print(
                "[KUBAPP AI] WARNING: Failed to commit or push the "
                f"rejection report: {exc}"
            )
        raise RuntimeError(
            "KUBAPP rejected the artifact following its security "
            f"assessment: {reason}"
        )

    print("[KUBAPP AI] Assessment passed.")
    return report
