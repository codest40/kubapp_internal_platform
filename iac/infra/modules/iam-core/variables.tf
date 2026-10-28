variable "cluster_name" {
  description = "EKS cluster name (used for naming IAM roles)"
  type        = string
}

variable "tf_state_bucket" {
  type = string
}

variable "database_account_arn" {
  type = string
}

variable "enable_db_cross_account" {
  type = bool
}

variable "enable_cross_account" {
  type = bool
}

variable "cross_account_role_arn" {
  type = string
}

variable "kubapp_account_user_arn" {
  type = string
}

variable "kubapp_account_user" {
  type = string
}

variable "visitor_account_user_arn" {
  type = string
}

variable "admin_github_arn" {
  type = string
}

variable "sys_monitor_account_user" {
  type = string
}

variable "sys_monitor_account_user_arn" {
  type = string
}

variable "fargate_log_group_arn" {
  description = "ARN of the CloudWatch log group used by Fargate workloads"
  type        = string
}

variable "account_id" {
  type = string
}

variable "zone_id" {
  type = string
}

variable "tags" {
  description = "Tags applied to all IAM resources"
  type        = map(string)
  default     = {}
}
