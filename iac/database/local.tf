data "aws_caller_identity" "current" {}

locals {
  account_id         = data.aws_caller_identity.current.account_id
  kubapp_account_id  = var.kubapp_account_id
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
  skip_final_snapshot       = true
  final_snapshot_identifier = "${local.project}-${local.env}-database-final"

  # sys_monitor conn
  sys_monitor_enabled            = var.sys_monitor_enabled
  sys_monitor_cross_mode_enabled = var.sys_monitor_cross_mode_enabled

  sys_monitor_local_mode_enabled = (
    local.sys_monitor_enabled &&
    !local.sys_monitor_cross_mode_enabled
  )

  sys_monitor_state = (
    local.sys_monitor_local_mode_enabled ? "local"
    : local.sys_monitor_enabled && local.sys_monitor_cross_mode_enabled ? "cross"
    : "disabled"
  )

  sys_monitor_cross_mode_vpc_cidr = "10.40.0.0/16"
  sys_monitor_local_mode_vpc_cidr = local.derived_vpc_cidr
  derived_vpc_cidr = (
    local.sys_monitor_state == "local" &&
    local.account_vpc_cidr == "10.20.0.0/16" ? "10.20.0.0/16"
    : local.sys_monitor_state == "local" ? "10.0.0.0/16"
    : ""
  )

  sys_monitor_database_cidrs = concat(
    local.sys_monitor_local_mode_enabled
    ? [local.sys_monitor_local_mode_vpc_cidr]
    : [],

    local.sys_monitor_enabled && local.sys_monitor_cross_mode_enabled
    ? [local.sys_monitor_cross_mode_vpc_cidr]
    : []
  )
}
