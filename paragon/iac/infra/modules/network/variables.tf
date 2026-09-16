variable "name" {
  description = "Base name for the network resources"
  type        = string
}

variable "cluster_name" {
  description = "helper tag for downward resources"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}


variable "vpc_flow_log_arn" {
  description = "CloudWatch log group configuration for VPC flow logs"
  type        = string
}

variable "azs" {
  description = "List of availability zones"
  type        = list(string)
}

variable "public_subnets" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
}

variable "private_subnets" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
}

variable "tags" {
  description = "Base ags for the network resources"
  type        = map(string)
  default     = {}
}
