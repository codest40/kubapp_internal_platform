terraform {
  required_version = "~> 1.14"

  backend "local" {}
}

provider "aws" {
  region  = var.region
  profile = var.profile
}

locals {
  admin_iam_arn = "arn:aws:iam::${var.account_id}:user/${var.profile}"
}

resource "aws_iam_role" "sys_monitor" {
  name = "sys-monitor-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "ec2.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      },
      {
        Effect = "Allow"

        Principal = {
          AWS = local.admin_iam_arn
        }

        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_user_policy" "assume_sys_monitor_role" {
  user = var.profile

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"

      Action = "sts:AssumeRole"

      Resource = aws_iam_role.sys_monitor.arn
    }]
  })
}

resource "aws_iam_role_policy" "terraform_management" {
  role = aws_iam_role.sys_monitor.name

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

      Resource = aws_iam_role.sys_monitor.arn
    }]
  })
}

variable "profile" {
  type = string
}

variable "account_id" {
  type = string
}

variable "kubapp_account_id" {
  type = string
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "access_mode" {
  type = string
}

resource "aws_iam_role_policy" "cross_account_assume" {
  role = aws_iam_role.sys_monitor.name

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Sid      = "AllowCrossAccountAssume"
      Effect   = "Allow"
      Action   = "sts:AssumeRole"
      Resource = "arn:aws:iam::${var.kubapp_account_id}:role/sys-monitor-cross-account-role"
    }]
  })

  depends_on = [
    aws_iam_role.sys_monitor
  ]
}


resource "aws_iam_instance_profile" "sys_monitor" {
  name = "sys-monitor-ec2-profile"
  role = aws_iam_role.sys_monitor.name
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.sys_monitor.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

