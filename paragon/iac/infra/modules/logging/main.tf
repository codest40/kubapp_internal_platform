
resource "aws_cloudwatch_log_group" "logs" {
  for_each = var.log_groups

  name              = each.value.name
  retention_in_days = each.value.retention

  tags = merge(var.tags, {
    resource-type = "cloudwatch-log-group"
    cluster       = var.cluster_name
    eni-cluster   = var.cluster_name
    log-type      = each.value.log_type
    log-scope     = each.value.scope
    log-name      = each.key
  })
}


output "log_group_names" {
  value = { for k, v in aws_cloudwatch_log_group.logs : k => v.name }
}

output "log_group_arns" {
  value = { for k, v in aws_cloudwatch_log_group.logs : k => v.arn }
}
