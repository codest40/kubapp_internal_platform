from k8s_client import K8sClientFactory
import os

from metrics import (
    gitops_app_total,
    gitops_app_healthy_total,
    gitops_app_out_of_sync_total,
    gitops_app_degraded_total,
    gitops_drift_ratio,
    gitops_convergence_score
)

GROUP = "argoproj.io"
VERSION = "v1alpha1"
PLURAL = "applications"


def collect_metrics():
    try:
        api = K8sClientFactory.get_clients()
        custom = api["custom"]

        # =========================================================
        # DEBUG (optional)
        # =========================================================
        if os.getenv("ENABLE_NODE_DEBUG", "false").lower() == "true":
            v1 = api["core"]
            nodes = v1.list_node()

            print(f"[DEBUG] Nodes found: {len(nodes.items)}")
            for n in nodes.items[:3]:
                print(f"[DEBUG] Node: {n.metadata.name}")

        # =========================================================
        # ArgoCD Applications (single API call)
        # =========================================================
        response = custom.list_cluster_custom_object(
            group=GROUP,
            version=VERSION,
            plural=PLURAL
        )

        apps = response.get("items", [])

        total = len(apps)
        healthy = 0
        out_of_sync = 0
        degraded = 0

        for app in apps:
            status = app.get("status", {})

            health = status.get("health", {}).get("status", "")
            sync = status.get("sync", {}).get("status", "")

            if health == "Healthy":
                healthy += 1

            if sync != "Synced":
                out_of_sync += 1

            if health in ["Degraded", "Missing"]:
                degraded += 1

        drift_ratio = (out_of_sync / total) if total else 0
        convergence = (healthy / total) if total else 0

        gitops_app_total.set(total)
        gitops_app_healthy_total.set(healthy)
        gitops_app_out_of_sync_total.set(out_of_sync)
        gitops_app_degraded_total.set(degraded)
        gitops_drift_ratio.set(drift_ratio)
        gitops_convergence_score.set(convergence)

    except Exception as e:
        print(f"[GitOps ERROR] {e}")
