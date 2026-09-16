variable "cluster_name" {
  description = "EKS cluster name (used for naming IAM roles)"
  type        = string
}

variable "tf_state_bucket" {
  type = string
}

variable "account_id" {
  type = string
}

variable "tags" {
  description = "Tags applied to all IAM resources"
  type        = map(string)
  default     = {}
}
