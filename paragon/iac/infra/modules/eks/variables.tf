variable "cluster_name" {
  type = string
}

variable "access_iam_arn" {
  type = string
}

variable "admin_arn" {
  type = string
}

variable "sys_monitor_eks_cross_account_role_arn" {
  description = "IAM role ARN used by the sys_monitor EC2 instance"
  type        = string
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

variable "sg_ids" {
  type = map(string)
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
  type = map(object({
    role   = string
    labels = optional(map(string), {})
  }))

  default = {
    dev = {
      role = "applications"
      labels = {
        compute = "fargate"
      }
    }

    prod = {
      role = "applications"
      labels = {
        compute = "fargate"
      }
    }
  }
}
