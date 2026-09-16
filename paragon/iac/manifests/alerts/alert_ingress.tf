resource "kubernetes_manifest" "alert_ingress" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PrometheusRule"

    metadata = {
      name      = "alert-ingress"
      namespace = "monitoring"

      labels = {
        release = "kube-prometheus-stack"
        tier    = "ingress"
        domain  = "slo"
      }
    }

    spec = {
      groups = [
        {
          name = "ingress.slo.rules"

          rules = [
            # ---------------------------
            # 5xx Error Rate
            # ---------------------------
            {
              alert = "IngressHigh5xxRate"

              expr = <<EOT
sum(rate(nginx_ingress_controller_requests{status=~"5.."}[5m]))
/
sum(rate(nginx_ingress_controller_requests[5m])) > 0.05
EOT

              for = "5m"

              labels = {
                severity = "critical"
              }

              annotations = {
                summary = "High ingress 5xx error rate"
              }
            },

            # ---------------------------
            # No Traffic
            # ---------------------------
            {
              alert = "IngressNoTraffic"

              expr = "sum(rate(nginx_ingress_controller_requests[10m])) == 0"
              for  = "15m"

              labels = {
                severity = "warning"
              }

              annotations = {
                summary = "No traffic detected at ingress"
              }
            },

            # ---------------------------
            # High Latency (p95)
            # ---------------------------
            {
              alert = "IngressHighLatency"

              expr = <<EOT
histogram_quantile(0.95,
  sum(rate(nginx_ingress_controller_request_duration_seconds_bucket[5m])) by (le)
) > 1
EOT

              for = "5m"

              labels = {
                severity = "warning"
              }

              annotations = {
                summary = "Ingress latency above 1s"
              }
            },

            # ---------------------------
            # Backend Failure (502)
            # ---------------------------
            {
              alert = "IngressBackendFailure"

              expr = "rate(nginx_ingress_controller_requests{status=\"502\"}[5m]) > 0"
              for  = "5m"

              labels = {
                severity = "critical"
              }

              annotations = {
                summary = "Backend returning 502 errors"
              }
            },

            # ---------------------------
            # TLS Expiry Warning
            # ---------------------------
            {
              alert = "IngressTLSExpiringSoon"

              expr = "nginx_ingress_controller_ssl_expire_time_seconds < 604800"
              for  = "1h"

              labels = {
                severity = "warning"
              }

              annotations = {
                summary = "TLS certificate expiring within 7 days"
              }
            }
          ]
        }
      ]
    }
  }

}
