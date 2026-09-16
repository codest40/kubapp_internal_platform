############################################
# OUTPUTS
############################################

output "eks_cluster_role_arn" {
  description = "IAM role ARN for EKS control plane"
  value       = aws_iam_role.eks_cluster.arn
}

output "node_group_role_arn" {
  description = "IAM role ARN for EC2 node group"
  value       = aws_iam_role.node_group.arn
}

output "fargate_role_arn" {
  description = "IAM role ARN for Fargate pods"
  value       = aws_iam_role.fargate.arn
}

output "sys_monitor_ec2_role_arn" {
  description = "IAM role ARN for system monite pods"
  value       = aws_iam_role.ec2_role.arn
}

output "sys_monitor_instance_profile_name" {
  value = aws_iam_instance_profile.ec2_profile.name
}

output "sys_monitor_eks_cross_account_role" {
  value = aws_iam_role.sys_monitor_cross_account_role.arn
}
