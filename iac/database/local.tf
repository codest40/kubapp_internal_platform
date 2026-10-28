data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id

  cross_mode_enabled = local.account_id != var.kubapp_account_id

  project = data.terraform_remote_state.infra.outputs.project
  env     = data.terraform_remote_state.infra.outputs.env
  region  = data.terraform_remote_state.infra.outputs.region

  kubapp_account_vpc_id = (
    data.terraform_remote_state.infra.outputs.vpc_id
  )

  kubapp_account_vpc_cidr = (
    data.terraform_remote_state.infra.outputs.vpc_cidr
  )

  sg_boundary_id = (
    data.terraform_remote_state.infra.outputs.db_access_security_group_id
  )

  ec2_node_sg_id = (
    data.terraform_remote_state.infra.outputs.cluster_security_group_id
  )

  account_vpc_cidr = (
    local.cross_mode_enabled
    ? "10.20.0.0/16"
    : local.kubapp_account_vpc_cidr
  )

  multi_az                  = true
  storage_encrypted         = true
  database_port             = 5432
  deletion_protection       = false
  skip_final_snapshot       = true #false
  final_snapshot_identifier = "${local.project}-${local.env}-database-final"
}
