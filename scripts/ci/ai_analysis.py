import json
import threading
from pathlib import Path

from ai.client import mcp_entry


RULES_DIR = Path(__file__).resolve().parent / "ai" / "rules"
AI_ASSESSMENT_LOCK = threading.Lock()
RULE_FILES = {
    "command": "commands.json",
    "script": "scripts.json",
    "module": "modules.json",
    "dockerfile": "dockerfile.json",
}
RECOMMENDATION_PRIORITIES = {"low", "medium", "high"}


def analyze_data(args):
    """
    Assess a KUBAPP CI artifact before execution or use.
    """
    if not isinstance(args, dict):
        raise TypeError("Execution context must be a dictionary.")

    if not args:
        raise ValueError("Execution context cannot be empty.")

    artifact_type = args.get("artifact_type")
    if artifact_type not in RULE_FILES:
        raise ValueError(
            f"Artifact type {artifact_type} NOT Supported!!"
        )
    if not isinstance(artifact_type, str):
        raise ValueError(
            "Execution context must specify an artifact_type."
        )

    rules_filename = RULE_FILES.get(artifact_type)
    if rules_filename is None:
        raise ValueError(
            f"Unsupported artifact_type: {artifact_type!r}. "
            f"Supported types: {', '.join(RULE_FILES)}."
        )

    rules_file_path = RULES_DIR / rules_filename
    if not rules_file_path.is_file():
        raise RuntimeError(
            f"KUBAPP security rules not found: {rules_file_path}"
        )

    try:
        with rules_file_path.open("r", encoding="utf-8") as rules_file:
            rules = json.load(rules_file)
    except (OSError, json.JSONDecodeError) as exc:
        raise RuntimeError(
            f"Failed to load KUBAPP security rules: {exc}"
        ) from exc

    ruleset_id = rules.get("ruleset_id")
    ruleset_version = rules.get("ruleset_version")

    if not isinstance(ruleset_id, str) or not ruleset_id.strip():
        raise RuntimeError(
            f"Invalid ruleset configuration: ruleset_id is missing "
            f"from {rules_filename}."
        )

    if (
        not isinstance(ruleset_version, str)
        or not ruleset_version.strip()
    ):
        raise RuntimeError(
            f"Invalid ruleset configuration: ruleset_version is "
            f"missing from {rules_filename}."
        )

    if rules.get("artifact_type") != artifact_type:
        raise RuntimeError(
            f"Ruleset artifact_type does not match the requested "
            f"artifact type {artifact_type!r}."
        )

    request = {
        "context": args,
        "rules": rules,
    }

    app_name = args.get("app_name")
    try:
        with AI_ASSESSMENT_LOCK:
            print(
                f"ℹ️  Locked Resource: AI_ASSESSMENT Ongoing "
                f"for {app_name} build"
            )
            result = mcp_entry(request)
            print(f"✅ AI_ASSESSMENT Completed for {app_name}")
    except Exception as exc:
        raise RuntimeError(
            "KUBAPP security assessment failed. "
            f"The {app_name} {artifact_type} must not proceed. "
            f"Reason: {exc}"
        ) from exc

    if not isinstance(result, dict):
        raise RuntimeError(
            "Invalid assessment response: expected a dictionary."
        )

    decision = result.get("decision")
    reason = result.get("reason")
    evidence = result.get("evidence")
    recommendations = result.get("recommendations")

    if type(decision) is not int or decision not in (0, 1):
        raise RuntimeError(
            "Invalid assessment response: decision must be 0 or 1."
        )

    if not isinstance(reason, str) or not reason.strip():
        raise RuntimeError(
            "Invalid assessment response: reason is required."
        )

    if (
        not isinstance(evidence, list)
        or not all(
            isinstance(item, str) and item.strip()
            for item in evidence
        )
    ):
        raise RuntimeError(
            "Invalid assessment response: evidence must be "
            "a list of non-empty strings."
        )

    if not isinstance(recommendations, list):
        raise RuntimeError(
            "Invalid assessment response: recommendations must "
            "be a list."
        )

    for index, recommendation in enumerate(recommendations):
        if not isinstance(recommendation, dict):
            raise RuntimeError(
                "Invalid assessment response: recommendation "
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
                "Invalid assessment response: recommendation "
                f"{index} has an invalid priority."
            )

        if not isinstance(action, str) or not action.strip():
            raise RuntimeError(
                "Invalid assessment response: recommendation "
                f"{index} requires a non-empty action."
            )

        if not isinstance(rationale, str) or not rationale.strip():
            raise RuntimeError(
                "Invalid assessment response: recommendation "
                f"{index} requires a non-empty rationale."
            )

    return {
        "ruleset_id": ruleset_id,
        "ruleset_version": ruleset_version,
        "artifact_type": artifact_type,
        "app_name": args.get("app_name", "unknown"),
        "decision": decision,
        "reason": reason,
        "evidence": evidence,
        "recommendations": recommendations,
    }
