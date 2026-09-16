resource "aws_eks_node_group" "system_nodes" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.cluster_name}-system-nodes"
  node_role_arn   = var.node_role_arn

  subnet_ids = var.private_subnet_ids

  scaling_config {
    desired_size = var.sys_node_desired_capacity
    max_size     = var.sys_node_max_capacity
    min_size     = var.sys_node_min_capacity
  }

  instance_types = [var.sys_node_instance_type]

  ami_type  = "AL2023_x86_64_STANDARD"
  disk_size = 30

  labels = {
    node_type = "system"
    compute   = "system"
  }

  update_config {
    max_unavailable = 1
  }

  tags = merge(var.tags, {
    Name          = "${var.cluster_name}-system-node"
    resource-type = "eks-node-group"
    eks-scope     = "system-node-group"
    node-type     = "ec2"
    node-group    = "secondary"
    node-role     = "worker"
    workload      = "system"
    eni-cluster   = var.cluster_name
    eni-domain    = "compute"
    capacity-type = "on-demand"
  })

}
