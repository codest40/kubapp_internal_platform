
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
