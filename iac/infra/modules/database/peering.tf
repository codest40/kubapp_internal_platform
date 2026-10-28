resource "aws_vpc_peering_connection_accepter" "database" {
  count = var.allow_kubapp_read_db_state && var.enable_db_cross_account ? 1 : 0

  vpc_peering_connection_id = (
    data.terraform_remote_state.database[0].outputs.database_peering_connection_id
  )

  auto_accept = true

  tags = merge(var.tags, {
    resource-type = "vpc-peering-accepter"
  })
}
