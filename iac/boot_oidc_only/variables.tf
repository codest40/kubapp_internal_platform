
variable "github_repository_owner" {
  type = string
}

variable "github_repository_owner_id" {
  type = string
}

variable "github_repository_name" {
  type = string
}

variable "github_repository_id" {
  type = string
}

variable "github_environments" {
  type = list(string)
}

variable "github_branches" {
  type = list(string)
}

variable "github_actions_role_name" {
  type = string
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "profile" {
  type = string
}
