
resource "aws_eks_access_entry" "admin_access" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = var.github_iam_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "access_admin_policy" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = var.github_iam_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }
  depends_on = [
    aws_eks_access_entry.admin_access
  ]
}

resource "aws_eks_access_entry" "from_laptop" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = var.admin_iam_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "from_laptop" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_eks_access_entry.from_laptop.principal_arn

  policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }
}

resource "aws_eks_access_entry" "sys_monitor" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = var.sys_monitor_ec2_role_arn
  type          = "STANDARD"
  kubernetes_groups = [
    var.sys_monitor_rbac_group_name
  ]
}

resource "aws_eks_access_entry" "sys_monitor_cross_account" {
  count         = var.enable_cross_account ? 1 : 0
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = var.sys_monitor_eks_cross_account_role_arn
  type          = "STANDARD"
  kubernetes_groups = [
    var.sys_monitor_rbac_group_name
  ]
}


