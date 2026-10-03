variable "profile" {
  type = string
}

variable "account_id" {
  type = string
}

variable "env" {
  type = string
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "kubapp_account_id" {
  description = "KUBAPP AWS account ID"
  type        = string
}

variable "cluster_mode" {
  type = string
  validation {
    condition     = contains(["local", "cross"], var.cluster_mode)
    error_message = "cluster_mode must be local or cross."
  }
}

variable "access_mode" {
  type = string
  validation {
    condition     = contains(["ssm", "ssh"], var.access_mode)
    error_message = "access_mode must be ssm or ssh."
  }
}

