resource "kubernetes_manifest" "alert_infra" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PrometheusRule"

    metadata = {
      name      = "alert-infra"
      namespace = "monitoring"

      labels = {
        release = "kube-prometheus-stack"
        tier    = "infra"
        domain  = "slo"
      }
    }

    spec = {
      groups = [
        {
          name = "infra.slo.rules"

          rules = [
            # ---------------------------
            # Node Not Ready
            # ---------------------------
            {
              alert = "NodeNotReady"

              expr = "kube_node_status_condition{condition=\"Ready\",status=\"true\"} == 0"
              for  = "5m"

              labels = {
                severity = "critical"
              }

              annotations = {
                summary = "A node is not ready"
              }
            },

            # ---------------------------
            # Memory Pressure
            # ---------------------------
            {
              alert = "NodeMemoryPressure"

              expr = "node_memory_MemAvailable / node_memory_MemTotal < 0.1"
              for  = "10m"

              labels = {
                severity = "critical"
              }

              annotations = {
                summary = "Severe memory pressure on node"
              }
            },

            # ---------------------------
            # Disk Pressure
            # ---------------------------
            {
              alert = "NodeDiskPressure"

              expr = "node_filesystem_avail_bytes / node_filesystem_size_bytes < 0.1"
              for  = "10m"

              labels = {
                severity = "critical"
              }

              annotations = {
                summary = "Low disk space on node"
              }
            },

            # ---------------------------
            # OOMKilled Pods
            # ---------------------------
            {
              alert = "PodOOMKilled"

              expr = "increase(kube_pod_container_status_restarts_reason{reason=\"OOMKilled\"}[10m]) > 0"
              for  = "5m"

              labels = {
                severity = "critical"
              }

              annotations = {
                summary = "Pod was OOMKilled"
              }
            },

            # ---------------------------
            # CPU Throttling (hidden killer)
            # ---------------------------
            {
              alert = "ContainerCPUThrottling"

              expr = "rate(container_cpu_cfs_throttled_seconds_total[5m]) > 0.5"
              for  = "10m"

              labels = {
                severity = "warning"
              }

              annotations = {
                summary = "Severe CPU throttling detected"
              }
            }
          ]
        }
      ]
    }
  }
}
