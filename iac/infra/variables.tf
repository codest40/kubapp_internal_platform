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

variable "access_iam_arn" {
  type      = string
  sensitive = true
}


variable "admin_arn" {
  type      = string
  sensitive = true
}

variable "account_id" {
  type      = string
  sensitive = true
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

