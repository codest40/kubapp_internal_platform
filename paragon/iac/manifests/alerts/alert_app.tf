resource "kubernetes_manifest" "alert_app" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PrometheusRule"

    metadata = {
      name      = "alert-app"
      namespace = "monitoring"

      labels = {
        release = "kube-prometheus-stack"
        tier    = "app"
        domain  = "slo"
      }
    }

    spec = {
      groups = [
        {
          name = "app.slo.rules"

          rules = [
            # ---------------------------
            # 1. Service Error Rate (SLO)
            # ---------------------------
            {
              alert = "AppHighErrorRate"

              expr = <<EOT
sum(rate(http_requests_total{status=~"5.."}[5m]))
/
sum(rate(http_requests_total[5m])) > 0.05
EOT

              for = "5m"

              labels = {
                severity = "critical"
                team     = "platform"
              }

              annotations = {
                summary     = "High API error rate detected"
                description = "More than 5% of requests are failing (5xx)."
              }
            },

            # ---------------------------
            # 2. Latency SLO (p95)
            # ---------------------------
            {
              alert = "AppHighLatency"

              expr = <<EOT
histogram_quantile(0.95,
  sum(rate(http_request_duration_seconds_bucket[5m])) by (le)
) > 1
EOT

              for = "5m"

              labels = {
                severity = "warning"
                team     = "platform"
              }

              annotations = {
                summary = "High request latency detected"
              }
            },

            # ---------------------------
            # 3. CrashLoop Protection
            # ---------------------------
            {
              alert = "AppCrashLooping"

              expr = "increase(kube_pod_container_status_restarts_total[15m]) > 5"
              for  = "10m"

              labels = {
                severity = "critical"
                team     = "platform"
              }

              annotations = {
                summary = "Pod is restarting frequently"
              }
            },

            # ---------------------------
            # 4. Service Down (no endpoints)
            # ---------------------------
            {
              alert = "AppServiceDown"

              expr = "kube_endpoint_address_available == 0"
              for  = "5m"

              labels = {
                severity = "critical"
                team     = "platform"
              }

              annotations = {
                summary = "No active endpoints for service"
              }
            }
          ]
        }
      ]
    }
  }
}
