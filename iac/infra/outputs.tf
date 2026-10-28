
output "lb_controller_role_arn" {
  value = module.iam_irsa.lb_controller_role_arn
}

output "app_pods_role_arn" {
  value = module.iam_irsa.app_pods_role_arn
}

output "ebs_csi_irsa_arn" {
  value = module.iam_irsa.ebs_csi_irsa_arn
}

output "fluentbit_role_arn" {
  value = module.iam_irsa.fluentbit_role_arn
}

output "efs_role_arn" {
  value = module.iam_irsa.efs_role_arn
}

output "efs_id" {
  value = module.efs.efs_id
}

output "efs_dns_name" {
  value = module.efs.efs_dns_name
}

output "efs_security_group_id" {
  value = module.efs.efs_security_group_id
}

output "cluster_security_group_id" {
  value = module.eks.cluster_security_group_id
}

output "ec2_app_security_group_id" {
  value = module.security.sg_ids["ec2_app"]
}

output "ec2_app_workloads" {
  value = local.workloads.labels_ec2
}

output "fargate_app_security_group_id" {
  value = module.security.sg_ids["fargate_app"]
}

output "fargate_workloads" {
  value = local.workloads.labels_fargate
}

output "vpc_id" {
  value = module.network.vpc_id
}

output "vpc_cidr" {
  value = local.vpc_cidr
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_ca_certificate" {
  value = module.eks.cluster_ca_certificate
}

output "log_group_names" {
  value = module.logging.log_group_names
}

output "external_dns_role_arn" {
  value = module.iam_irsa.external_dns_role_arn
}

output "env" {
  value = var.env
}

output "project" {
  value = var.project
}

output "region" {
  value = var.region
}

output "kubapp_account_id" {
  value = local.account_id
}

output "name_prefix" {
  value = local.name_prefix
}

output "common_tags" {
  value = local.common_tags
}

output "full_domain" {
  value = local.full_domain
}

output "domain" {
  value = local.main_domain
}

output "cert_arn" {
  value = module.acm.acm_cert_arn
}

output "sys_monitor_ec2_role_arn" {
  value = module.iam_core.sys_monitor_ec2_role_arn
}

output "sys_monitor_instance_profile_name" {
  value = module.iam_core.sys_monitor_instance_profile_name
}

output "sys_monitor_eks_cross_account_role_Visitor" {
  value = local.enable_cross_account ? local.cross_account_role_arn : null
}

output "kubapp_eks_cross_account_role_Receiver" {
  value = try(module.iam_core.sys_monitor_eks_cross_account_role, null)
}

output "sys_monitor_terraform_execution_role" {
  value = module.iam_core.sys_monitor_terraform_execution_role
}

output "sys_monitor_rbac_group_name" {
  value = module.eks.sys_monitor_rbac_group_name
}

output "dns_zone_id" {
  value = local.dns_zone_id
}

output "db_access_security_group_id" {
  value = module.security.sg_ids["db_access"]
}

output "private_subnet_ids" {
  value = module.network.private_subnet_ids
}

output "kubapp_db_cross_account_role_Visitor" {
  value = local.enable_db_cross_account ? local.database_account_arn : null
}

output "kubapp_db_cross_account_role_Receiver" {
  value = try(module.iam_core.database_account_terraform_role, null)
}

output "kubapp_reads_db_state" {
  value = try(module.database.kubapp_reads_db_state, null)
}

output "db_lets_kubapp_read_state_arn" {
  value = try(local.db_lets_kubapp_read_state_arn, null)
}

output "show_database_state" {
  value = local.show_database_state
}
