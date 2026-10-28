
variable "kubapp_account_id" {
  type = string
}

variable "env" {
  type = string
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "engine_version" {
  type = string
}

variable "instance_class" {
  type = string
}

variable "allocated_storage" {
  type = number
}

variable "max_allocated_storage" {
  type = number
}

variable "storage_type" {
  type    = string
  default = "gp3"
}

variable "iops" {
  type    = number
  default = null
}

variable "storage_throughput" {
  type    = number
  default = null
}

variable "backup_retention_period" {
  type    = number
  default = 7
}

variable "backup_window" {
  type = string
}

variable "maintenance_window" {
  type = string
}

variable "database_name" {
  type = string
}

variable "master_username" {
  type      = string
  sensitive = true
}

variable "master_password" {
  type      = string
  sensitive = true
}

variable "state_bucket" {
  type = string
}

variable "state_key" {
  type = string
}
