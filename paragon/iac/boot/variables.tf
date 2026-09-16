
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

variable "lock_table_name" {
  description = "DynamoDB table name for Terraform state locking"
  type        = string
}

variable "github_actions_role_name" {
  description = "IAM role assumed by GitHub Actions"
  type        = string
  default     = "kubapp-github-actions"
}

variable "github_repository_owner" {
  description = "GitHub repository owner"
  type        = string
}

variable "github_repository_name" {
  description = "GitHub repository name"
  type        = string
}

variable "github_repository_owner_id" {
  description = "Immutable GitHub repository owner ID"
  type        = string
}

variable "github_repository_id" {
  description = "Immutable GitHub repository ID"
  type        = string
}

variable "github_branches" {
  description = "GitHub branches allowed to assume the Terraform role"
  type        = list(string)
  default     = ["main"]
}

variable "github_environments" {
  description = "GitHub environments allowed to assume the Terraform role"
  type        = list(string)
  default     = ["dev", "prod"]
}
