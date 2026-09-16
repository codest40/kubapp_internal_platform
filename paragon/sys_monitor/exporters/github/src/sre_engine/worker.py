import time
from prometheus_client import start_http_server
from stream.event_bus import query_events_since

from metrics.health import (
    compute_health_score,
    detect_anomaly,
    slo_success_rate,
    error_budget_burn_rate,
    error_budget_remaining,
    github_health_score,
    github_anomaly_flag,
)

from metrics.registry import (
    github_push_total,
    github_pr_total,
    github_workflow_run_total,
    github_workflow_job_total,
    github_issue_total,
)

# ============================================================
# CONFIG
# ============================================================

SLO_TARGET = 0.95
ERROR_BUDGET = 1.0 - SLO_TARGET

WINDOW_SECONDS = 300  # 5 minutes


# ============================================================
# PURE SLI COMPUTATION
# ============================================================

def compute_sli(workflow_events):
    if not workflow_events:
        return 1.0

    success = sum(1 for e in workflow_events if e["success"])
    return success / len(workflow_events)


def compute_error_rate(sli):
    return 1.0 - sli


def compute_burn_rate(error_rate):
    if ERROR_BUDGET == 0:
        return 0.0
    return error_rate / ERROR_BUDGET


# ============================================================
# WORKER LOOP (HISTORICAL SQLITE SLO)
# ============================================================

def run_worker():
    print("[SRE ENGINE] Worker started...")
    start_http_server(8000)
    while True:
        now = time.time()
        window_start = now - WINDOW_SECONDS

        # --------------------------------------------------------
        # READ REAL HISTORY FROM SQLITE
        # --------------------------------------------------------
        events = query_events_since(window_start)

        workflow_events = []

        # --------------------------------------------------------
        # PROCESS EVENTS
        # --------------------------------------------------------
        for event in events:
            repo = event.get("repo", "unknown")
            etype = event.get("event_type")
            payload = event.get("payload", {})

            # PUSH
            if etype == "push":
                github_push_total.labels(
                    repo=repo,
                    commit=payload.get("after", "unknown")
                ).inc()

            # PR
            elif etype == "pull_request":
                github_pr_total.labels(
                    repo=repo,
                    action=payload.get("action", "unknown")
                ).inc()

            # ISSUES
            elif etype == "issues":
                github_issue_total.labels(
                    repo=repo,
                    action=payload.get("action", "unknown"),
                    state=payload.get("issue", {}).get("state", "unknown"),
                ).inc()

            # WORKFLOW (REAL SLI SIGNAL)
            elif etype in (
                "workflow_run_success",
                "workflow_run_failure",
                "workflow_run_unknown"
            ):
                success = 1 if etype == "workflow_run_success" else 0

                workflow_events.append({
                    "repo": repo,
                    "success": success
                })

                run = payload.get("workflow_run", {})

                github_workflow_run_total.labels(
                    repo=repo,
                    workflow=run.get("name", "unknown"),
                    status=run.get("status", "unknown"),
                    conclusion="success" if etype == "workflow_run_success" else "failure",
                ).inc()

            # WORKFLOW JOB
            elif etype in (
                "workflow_job_in_progress",
                "workflow_job_completed",
                "workflow_job",
            ):
                job = payload.get("workflow_job", {})

                github_workflow_job_total.labels(
                    repo=repo,
                    job=job.get("name", "unknown"),
                    status=job.get("status", "unknown"),
                    conclusion=job.get("conclusion", "unknown"),
                ).inc()

        # --------------------------------------------------------
        # COMPUTE SLO (WINDOW BASED)
        # --------------------------------------------------------
        sli = compute_sli(workflow_events)
        error_rate = compute_error_rate(sli)
        burn_rate = compute_burn_rate(error_rate)
        remaining_budget = max(0.0, ERROR_BUDGET - error_rate)

        repo = "default"

        # --------------------------------------------------------
        # PROMETHEUS SLO METRICS
        # --------------------------------------------------------
        slo_success_rate.labels(repo=repo).set(sli)
        error_budget_burn_rate.labels(repo=repo).set(burn_rate)
        error_budget_remaining.labels(repo=repo).set(remaining_budget)

        # --------------------------------------------------------
        # HEALTH + ANOMALY
        # --------------------------------------------------------
        health = compute_health_score(sli, burn_rate)
        anomaly = detect_anomaly(sli, burn_rate)

        github_health_score.labels(repo=repo).set(health)

        github_anomaly_flag.labels(
            repo=repo,
            type="workflow"
        ).set(1 if anomaly else 0)

        # --------------------------------------------------------
        # LOG OUTPUT
        # --------------------------------------------------------
        print(
            f"[SLO] window={WINDOW_SECONDS}s "
            f"sli={sli:.3f} err={error_rate:.3f} "
            f"burn={burn_rate:.2f} "
            f"health={health:.1f} "
            f"anomaly={anomaly}"
        )

        time.sleep(5)

if __name__ == "__main__":
    run_worker()
