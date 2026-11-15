terraform {
  required_version = "~> 1.14"

  backend "local" {}
}

provider "aws" {
  region = var.region
}

data "aws_iam_role" "sys_monitor" {
  name = "sys-monitor-ec2-role"
}

resource "aws_iam_role_policy" "terraform_management" {
  role = data.aws_iam_role.sys_monitor.name

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Sid    = "AllowIAMRoleManagement"
      Effect = "Allow"

      Action = [
        "iam:GetRole",
        "iam:GetRolePolicy",
        "iam:PutRolePolicy",
        "iam:DeleteRolePolicy",
        "iam:ListRolePolicies"
      ]

      Resource = data.aws_iam_role.sys_monitor.arn
    }]
  })
}

variable "profile" {
  type = string
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "access_mode" {
  type = string
}
