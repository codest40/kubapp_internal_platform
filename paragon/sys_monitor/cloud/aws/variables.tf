variable "cluster_mode" {
  type    = string
  default = "local"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "kubapp-sys-monitor"
}

variable "kubapp_bucket" {
  type = string
}

variable "kubapp_infra_key" {
  type = string
}

variable "domain_name" {
  type    = string
  default = "rundailytest.site"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.small"
}

variable "key_name" {
  description = "Existing AWS key pair name"
  type        = string
  default     = "sys-monitor-key"
}

variable "zone_id" {
  description = "zone id"
  type        = string
}

variable "ssh_cidr" {
  description = "Public IP in CIDR format"
  type        = string
}

variable "eks_account_id" {
  type    = string
  default = ""
}
