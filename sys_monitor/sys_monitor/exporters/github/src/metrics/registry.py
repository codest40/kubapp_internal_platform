from prometheus_client import Counter, Histogram, Gauge

# Pushes
github_push_total = Counter(
    "github_push_total",
    "GitHub push events",
    ["repo", "commit"]
)

# Pull Requests
github_pr_total = Counter(
    "github_pr_total",
    "GitHub PR events",
    ["repo", "action"]
)

# Workflow runs
github_workflow_run_total = Counter(
    "github_workflow_run_total",
    "GitHub workflow runs",
    ["repo", "workflow", "status", "conclusion"]
)

github_workflow_duration_seconds = Histogram(
    "github_workflow_duration_seconds",
    "Workflow execution duration",
    ["repo", "workflow"]
)

# Releases
github_release_total = Counter(
    "github_release_total",
    "GitHub releases",
    ["repo", "tag", "version"]
)

# Issues
github_issue_total = Counter(
    "github_issue_total",
    "GitHub issue events",
    ["repo", "action", "state"]
)

# Lead time for changes
github_change_lead_time_seconds = Gauge(
    "github_change_lead_time_seconds",
    "Lead time from commit to release",
    ["repo", "tag"]
)

# Workflow jobs
github_workflow_job_total = Counter(
    "github_workflow_job_total",
    "GitHub workflow job events",
    ["repo", "job", "status", "conclusion"]
)
