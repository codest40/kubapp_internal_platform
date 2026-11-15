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
  value       = try(aws_iam_role.ec2_role[0].arn, null)
}

output "sys_monitor_instance_profile_name" {
  value = try(aws_iam_instance_profile.ec2_profile[0].name, null)
}

output "sys_monitor_eks_cross_account_role" {
  value = try(aws_iam_role.sys_monitor_cross_account_role[0].arn, null)
}

output "sys_monitor_terraform_execution_role" {
  value = try(aws_iam_role.sys_monitor_terraform[0].name, null)
}

output "database_account_terraform_role" {
  value = try(aws_iam_role.db_cross_account_role[0].arn, null)
}
