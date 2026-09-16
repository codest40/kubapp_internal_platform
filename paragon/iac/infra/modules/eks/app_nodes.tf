resource "aws_eks_node_group" "app_nodes" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.cluster_name}-app-nodes"
  node_role_arn   = var.node_role_arn

  subnet_ids = var.private_subnet_ids

  scaling_config {
    desired_size = var.node_desired_capacity
    max_size     = var.node_max_capacity
    min_size     = var.node_min_capacity
  }

  instance_types = [var.node_instance_type]

  ami_type  = "AL2023_x86_64_STANDARD"
  disk_size = 30

  labels = {
    node_type = "ec2"
    compute   = "ec2"
  }

  taint {
    key    = "compute"
    value  = "ec2"
    effect = "NO_SCHEDULE"
  }

  update_config {
    max_unavailable = 1
  }

  depends_on = [
    aws_eks_cluster.this
  ]

  tags = merge(var.tags, {
    Name          = "${var.cluster_name}-app-node"
    resource-type = "eks-node-group"
    eks-scope     = "app-node-group"
    node-type     = "ec2"
    node-group    = "primary"
    node-role     = "worker"
    workload      = "apps"
    eni-cluster   = var.cluster_name
    eni-domain    = "compute"
    capacity-type = "on-demand"
  })
}
