resource "kubernetes_manifest" "alert_test" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PrometheusRule"

    metadata = {
      name      = "kybapp-alert-test"
      namespace = "monitoring"

      labels = {
        release = "kube-prometheus-stack"
        tier    = "testing"
        domain  = "slo"
      }
    }

    spec = {
      groups = [
        {
          name = "test.rules"

          rules = [
            {
              alert = "KubappAlertAlwaysFiring"

              expr = "vector(1)"

              for = "0m"

              labels = {
                severity = "warning"
                tier     = "test"
              }

              annotations = {
                summary     = "TEST ALERT: This alert always fires to Ensure things are working fine"
                description = "Used to verify Alertmanager routing and notification delivery"
              }
            }
          ]
        }
      ]
    }
  }
}
