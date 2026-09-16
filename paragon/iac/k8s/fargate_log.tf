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
          log_group_name /aws/eks/kubapp-dev/fargate
          log_stream_prefix from-fargate-
          auto_create_group true
    EOF
  }

  depends_on = [
    kubernetes_namespace_v1.this["aws_observability"]
  ]
}
