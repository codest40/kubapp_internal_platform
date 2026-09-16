from prometheus_client import Gauge

github_health_score = Gauge(
    "github_health_score",
    "Derived system health score",
    ["repo"]
)

github_anomaly_flag = Gauge(
    "github_anomaly_flag",
    "Anomaly detection flag",
    ["repo", "type"]
)

slo_success_rate = Gauge(
    "slo_success_rate",
    "Observed SLO success rate",
    ["repo"]
)

error_budget_burn_rate = Gauge(
    "error_budget_burn_rate",
    "Error budget burn rate",
    ["repo"]
)

error_budget_remaining = Gauge(
    "error_budget_remaining",
    "Remaining error budget (window-based)",
    ["repo"]
)


def compute_health_score(sli: float, burn_rate: float) -> float:
    base = sli * 100

    if burn_rate > 1.0:
        penalty = min(50, (burn_rate - 1.0) * 50)
    else:
        penalty = 0

    return max(0.0, min(100.0, base - penalty))


def detect_anomaly(sli: float, burn_rate: float) -> bool:
    return sli < 0.90 or burn_rate > 1.0
