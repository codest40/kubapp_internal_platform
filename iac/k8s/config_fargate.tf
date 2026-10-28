resource "kubernetes_config_map_v1" "fargate_logging" {
  metadata {
    name      = "aws-logging"
    namespace = kubernetes_namespace_v1.this["aws-observability"].metadata[0].name
  }

  data = {
    "output.conf" = <<-EOF
      [OUTPUT]
          Name cloudwatch_logs
          Match *
          region us-east-1
          log_group_name ${local.fargate_logs}
          log_stream_prefix from-fargate-
          auto_create_group false
    EOF
  }

  depends_on = [
    kubernetes_namespace_v1.this["aws-observability"]
  ]
}

# Fargate SG Policy for sg-prep.fargate_app
resource "kubernetes_manifest" "fargate_app_sg_policy" {
  manifest = {
    apiVersion = "vpcresources.k8s.aws/v1beta1"
    kind       = "SecurityGroupPolicy"

    metadata = {
      name      = "fargate-app-sg"
      namespace = local.fargate_workloads.env
    }

    spec = {
      podSelector = {
        matchLabels = {
          compute = local.fargate_workloads.compute
        }
      }

      securityGroups = {
        groupIds = [
          local.fargate_app_sg_id,
          local.cluster_sg_id,
          local.db_access_sg_id
        ]
      }
    }
  }
}
