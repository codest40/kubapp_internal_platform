
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

output "vpc_id" {
  value = module.network.vpc_id
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

output "dns_zone_id" {
  value = local.dns_zone_id
}


