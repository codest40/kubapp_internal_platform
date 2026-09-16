resource "aws_eks_fargate_profile" "workloads" {
  for_each = var.fargate_workloads

  cluster_name           = aws_eks_cluster.this.name
  fargate_profile_name   = "${var.cluster_name}-${each.key}"
  pod_execution_role_arn = var.fargate_role_arn
  subnet_ids             = var.private_subnet_ids
  selector {
    namespace = each.key
    labels    = each.value.labels
  }

  tags = merge(var.tags, {
    name          = "${var.cluster_name}-${each.key}-fargate"
    resource-type = "eks-fargate-profile"
    eks-scope     = "fargate"
    node-type     = "fargate"
    node-role     = each.value.role
    namespace     = each.key
  })
}

resource "aws_security_group" "fargate_pods" {
  name   = "${var.cluster_name}-fargate-sg"
  vpc_id = var.vpc_id

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"

    security_groups = [
      var.sg_ids["ec2_app"]
    ]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    name          = "${var.cluster_name}-fargate-sg"
    resource-type = "security-group"
    layer         = "security"
    attached-to   = "fargate"
    cluster       = var.cluster_name
  })
}
