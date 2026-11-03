data "terraform_remote_state" "sys_monitor" {
  count = (
    var.allow_kubapp_read_sys_monitor_state &&
    var.sys_monitor_cross_account_enabled
  ) ? 1 : 0

  backend = "s3"

  config = {
    bucket  = var.sys_monitor_state_bucket
    key     = var.sys_monitor_state_key
    region  = var.region
    profile = "kubapp-reads-sys-monitor-state-role"
    assume_role = {
      role_arn = var.sys_monitor_state_reader_role_arn
    }
  }
}
