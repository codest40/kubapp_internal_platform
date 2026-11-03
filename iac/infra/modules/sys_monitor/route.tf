resource "aws_route" "sys_monitor" {
  for_each = (
    var.allow_kubapp_read_sys_monitor_state &&
    var.sys_monitor_cross_account_enabled
  ) ? toset(var.kubapp_private_route_table_ids) : toset([])

  route_table_id = each.value

  destination_cidr_block = (
    data.terraform_remote_state.sys_monitor[0].outputs.sys_monitor_vpc_cidr
  )

  vpc_peering_connection_id = (
    aws_vpc_peering_connection_accepter.sys_monitor[0].id
  )
}
