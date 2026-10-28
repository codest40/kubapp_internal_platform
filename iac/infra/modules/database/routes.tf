resource "aws_route" "database" {
  for_each = (
    var.allow_kubapp_read_db_state &&
    var.enable_db_cross_account
    ? toset(var.kubapp_private_route_table_ids)
    : toset([])
  )

  route_table_id = each.value
  destination_cidr_block = (
    data.terraform_remote_state.database[0].outputs.database_vpc_cidr
  )

  vpc_peering_connection_id = (
    aws_vpc_peering_connection_accepter.database[0].id
  )
}
