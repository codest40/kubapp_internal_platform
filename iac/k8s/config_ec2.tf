resource "kubernetes_manifest" "ec2_app_sg_policy" {
  manifest = {
    apiVersion = "vpcresources.k8s.aws/v1beta1"
    kind       = "SecurityGroupPolicy"

    metadata = {
      name      = "ec2-app-sg"
      namespace = local.ec2_app_workloads.env
    }

    spec = {
      podSelector = {
        matchLabels = {
          compute = local.ec2_app_workloads.compute
        }
      }

      securityGroups = {
        groupIds = [
          local.ec2_app_sg_id,
          local.db_access_sg_id
        ]
      }
    }
  }
}
