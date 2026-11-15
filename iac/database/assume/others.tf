
terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region
}

locals {
  db_user_arn                      = "arn:aws:iam::${var.db_account_id}:user/${var.profile}"
  github_role_arn                  = "arn:aws:iam::${var.db_account_id}:role/${var.github_role}"
  kubapp_db_cross_account_role_arn = "arn:aws:iam::${var.kubapp_account_id}:role/db-cross-account-role"
}

output "db_terraform_role_name" {
  value = aws_iam_role.db_terraform.name
}

output "db_terraform_role_arn" {
  value = aws_iam_role.db_terraform.arn
}

output "kubapp_read_db_state_role_name" {
  value = aws_iam_role.kubapp_read_db_state.name
}

output "kubapp_read_db_state_role_arn" {
  value = aws_iam_role.kubapp_read_db_state.arn
}

output "sys_monitor_read_db_state_role_arn" {
  value = aws_iam_role.sys_monitor_read_db_state
}

output "sys_monitor_terraform_role" {
  value = aws_iam_role.sys_monitor_terraform
}
