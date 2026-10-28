resource "aws_eks_fargate_profile" "workloads" {

  cluster_name           = aws_eks_cluster.this.name
  fargate_profile_name   = "${var.cluster_name}-${var.fargate_workloads.env}"
  pod_execution_role_arn = var.fargate_role_arn
  subnet_ids             = var.private_subnet_ids
  selector {
    namespace = var.fargate_workloads.env
    labels = {
      compute = var.fargate_workloads.compute
    }
  }

  tags = merge(var.tags, {
    name          = "${var.cluster_name}-${var.fargate_workloads.env}-fargate"
    resource-type = "eks-fargate-profile"
    eks-scope     = "fargate"
    node-type     = "fargate"
    node-role     = "applications"
    namespace     = var.fargate_workloads.env
  })
}

