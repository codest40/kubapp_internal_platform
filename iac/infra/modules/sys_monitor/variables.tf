variable "sys_monitor_cross_account_enabled" {
  type    = bool
  default = false
}

variable "allow_kubapp_read_sys_monitor_state" {
  type    = bool
  default = false
}

variable "kubapp_vpc_id" {
  type = string
}

variable "kubapp_private_route_table_ids" {
  type = list(string)
}

variable "sys_monitor_account_id" {
  type = string
}

variable "sys_monitor_state_bucket" {
  type = string
}

variable "sys_monitor_state_key" {
  type = string
}

variable "sys_monitor_state_reader_role_arn" {
  type = string
}

variable "env" {
  type = string
}

variable "region" {
  type = string
}

variable "admin_kubapp_arn" {
  type = string
}

variable "admin_github_arn" {
  type = string
}

variable "tags" {
  type = map(string)
}
