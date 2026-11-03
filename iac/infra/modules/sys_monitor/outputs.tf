output "sys_monitor_peering_connection_id" {
  value = try(aws_vpc_peering_connection_accepter.sys_monitor[0].id, null)
}

output "sys_monitor_state_reader_role" {
  value = try(aws_iam_role.kubapp_sys_monitor_state_reader.name, null)
}
