output "eks_account_id" {
  value = local.eks_account_id
}

output "cluster_name" {
  value = local.cluster_name
}

output "running_mode" {
  value = var.cluster_mode
}

output "sys_monitor_public_ip" {
  value = aws_eip.sys_monitor.public_ip
}

output "grafana_url" {
  value = "https://graf.${local.domain_name}"
}

output "prometheus_url" {
  value = "https://prom.${local.domain_name}"
}

output "github_metrics_url" {
  value = "https://git.${local.domain_name}/metrics"
}

output "github_url" {
  value = "https://git.${local.domain_name}"
}

output "codebase_url" {
  value = "https://codebase.${local.domain_name}"
}

output "gitops_url" {
  value = "https://gitops.${local.domain_name}"
}
