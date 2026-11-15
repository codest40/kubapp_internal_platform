
output "database_endpoint" {
  value = aws_db_instance.database.address
}

output "sys_monitor_state" {
  value = local.sys_monitor_state
}

