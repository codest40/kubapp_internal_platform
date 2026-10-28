variable "enable_db_cross_account" {
  type = bool
}

variable "allow_kubapp_read_db_state" {
  type    = bool
  default = false
}

variable "admin_github_arn" {
  type = string
}

variable "admin_kubapp_arn" {
  type = string
}

variable "kubapp_vpc_id" {
  type = string
}

variable "kubapp_private_route_table_ids" {
  type = list(string)
}

variable "kubapp_vpc_cidr" {
  type = string
}

variable "database_account_id" {
  type = string
}

variable "database_state_bucket" {
  type = string
}

variable "database_state_key" {
  type = string
}

variable "db_lets_kubapp_read_state_arn" {
  type = string
}

variable "env" {
  type = string
}

variable "region" {
  type = string
}

variable "tags" {
  type = map(string)
}
