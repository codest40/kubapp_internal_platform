variable "cluster_name" {
  type = string
}

variable "github_iam_arn" {
  type = string
}

variable "admin_iam_arn" {
  type = string
}

variable "sys_monitor_ec2_role_arn" {
  description = "ARN used by the sys_monitor EC2 instance (same account)"
  type        = string
}

variable "sys_monitor_eks_cross_account_role_arn" {
  description = "ARN used by the sys_monitor EC2 instance (cross account)"
  type        = string
}

variable "sys_monitor_rbac_group_name" {
  type = string
}

variable "enable_cross_account" {
  type = bool
}

variable "kubernetes_version" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "node_instance_type" {
  type = string
}

variable "node_desired_capacity" {
  type = number
}

variable "node_min_capacity" {
  type = number
}

variable "node_max_capacity" {
  type = number
}

variable "sys_node_instance_type" {
  type = string
}

variable "sys_node_desired_capacity" {
  type = number
}

variable "sys_node_min_capacity" {
  type = number
}

variable "sys_node_max_capacity" {
  type = number
}

# IAM MODULE INPUTS
variable "cluster_role_arn" {
  type = string
}

variable "node_role_arn" {
  type = string
}

variable "fargate_role_arn" {
  type = string
}

variable "fargate_workloads" {
  type = object({
    compute = string
    env     = string
  })
}
