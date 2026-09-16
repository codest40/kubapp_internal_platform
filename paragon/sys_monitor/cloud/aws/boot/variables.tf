
variable "profile" {
  description = "AWS CLI profile used to create backend resources"
  type        = string
}

variable "region" {
  description = "AWS region for backend resources"
  type        = string
  default     = "us-east-1"
}

variable "state_bucket_name" {
  description = "S3 bucket name for Terraform remote state"
  type        = string
}

variable "force_destroy_bucket" {
  type    = bool
  default = true
}

