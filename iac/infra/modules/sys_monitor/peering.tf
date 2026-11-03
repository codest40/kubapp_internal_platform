resource "aws_vpc_peering_connection_accepter" "sys_monitor" {
  count = (
    var.allow_kubapp_read_sys_monitor_state &&
    var.sys_monitor_cross_account_enabled
  ) ? 1 : 0

  vpc_peering_connection_id = (
    data.terraform_remote_state.sys_monitor[0].outputs.sys_monitor_peering_connection_id
  )

  auto_accept = true

  tags = merge(var.tags, {
    resource-type = "vpc-peering-accepter"
  })
}
