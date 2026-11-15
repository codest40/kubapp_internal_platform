from flask import Blueprint, request, jsonify
from datetime import datetime, timezone

from stream.event_bus import publish
from stream.event_types import GitHubEvent

github_bp = Blueprint("github", __name__)


# ------------------------------------------------------------
# EVENT NORMALIZATION LAYER (CRITICAL FOR SLO CORRECTNESS)
# ------------------------------------------------------------

def normalize_event_type(event_type: str, payload: dict) -> str:
    """
    Converts raw GitHub event types into canonical internal events.
    This ensures SLO engine consistency.
    """

    if not event_type:
        return "unknown"

    # Workflow events
    if event_type == "workflow_run":
        conclusion = payload.get("workflow_run", {}).get("conclusion")

        if conclusion == "success":
            return "workflow_run_success"
        elif conclusion in ("failure", "cancelled", "timed_out", "action_required"):
            return "workflow_run_failure"

        return "workflow_run_unknown"

# Workflow job events
    if event_type == "workflow_job":
        action = payload.get("action", "unknown")
        if action == "in_progress":
            return "workflow_job_in_progress"
        elif action == "completed":
            return "workflow_job_completed"
        return "workflow_job"

    # Issues normalization
    if event_type == "issues":
        action = payload.get("action", "")
        if action in ("opened", "reopened"):
            return "issues_open"
        elif action in ("closed",):
            return "issues_closed"
        return "issues"

    # PR normalization
    if event_type == "pull_request":
        return "pull_request"

    return event_type


def extract_repo(payload: dict) -> str:
    repo = payload.get("repository", {}).get("full_name")
    return repo if repo else "unknown"


# ------------------------------------------------------------
# WEBHOOK ENTRYPOINT
# ------------------------------------------------------------

@github_bp.route("/webhook/github", methods=["POST"])
def github_webhook():
    event_type = request.headers.get("X-GitHub-Event", "unknown")
    payload = request.get_json(silent=True) or {}

    repo = extract_repo(payload)
    normalized_type = normalize_event_type(event_type, payload)

    event = GitHubEvent(
        event_type=normalized_type,
        repo=repo,
        payload=payload,
        timestamp=datetime.now(timezone.utc),
    )

    publish(event)

    return jsonify({
        "status": "ok",
        "event_type": normalized_type,
        "repo": repo
    }), 200
