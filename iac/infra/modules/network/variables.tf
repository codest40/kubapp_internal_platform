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

variable "private_subnet_azs" {
  description = "Availability Zone mapping for private subnets"
  type        = list(string)
}

variable "rds_proxy_private_subnet_indices" {
  description = "Private subnet indices selected for RDS Proxy, one per AZ"
  type        = list(number)
}

variable "workload_private_subnet_indices" {
  description = "Private subnet indices reserved for eks workloads"
  type        = list(number)
}

variable "tags" {
  description = "Base ags for the network resources"
  type        = map(string)
  default     = {}
}
