variable "env" {
  description = "Environment name"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.env)
    error_message = "env must be dev, staging, or prod."
  }
}

variable "project" {
  description = "Project name"
  type        = string
  default     = "kubapp"
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "admin_github" {
  type = string
}

variable "admin_kubapp" {
  type = string
}

variable "admin_visitor" {
  type = string
}

variable "admin_sys_monitor" {
  type = string
}

variable "database_role" {
  type = string
}

variable "cross_account_ids" {
  type = map(string)
  #default = null
}

variable "enable_db_local_account" {
  type    = bool
  default = true
}

variable "kubernetes_v" {
  description = "Kubernetes version"
  type        = string
  default     = "1.31"
}

variable "main_domain" {
  description = "Domain automatically provisioned used in k8s"
  type        = string
}

variable "cluster_name" {
  description = "Base cluster name (no env suffix here)"
  type        = string
}

variable "log_groups" {
  description = "CloudWatch log group definitions"
  type = map(object({
    retention = number
  }))
}

variable "sys_monitor_enabled" {
  type    = bool
  default = false
}

variable "db_enabled" {
  type    = bool
  default = false
}

variable "db_kubapp_reciever_role" {
  type = string
}
