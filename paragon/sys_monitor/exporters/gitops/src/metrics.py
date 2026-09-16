from prometheus_client import Gauge

# GitOps application totals
gitops_app_total = Gauge(
    "gitops_app_total",
    "Total number of GitOps applications"
)

gitops_app_healthy_total = Gauge(
    "gitops_app_healthy_total",
    "Number of healthy applications"
)

gitops_app_out_of_sync_total = Gauge(
    "gitops_app_out_of_sync_total",
    "Number of out-of-sync applications"
)

gitops_app_degraded_total = Gauge(
    "gitops_app_degraded_total",
    "Number of degraded applications"
)

gitops_drift_ratio = Gauge(
    "gitops_drift_ratio",
    "Ratio of out-of-sync applications"
)

gitops_convergence_score = Gauge(
    "gitops_convergence_score",
    "Overall GitOps convergence score"
)
