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
  region = var.aws_region
}

provider "aws" {
  alias  = "eks"
  region = var.aws_region
  dynamic "assume_role" {
    for_each = var.cluster_mode == "cross" ? [1] : []
    content {
      role_arn = "arn:aws:iam::${var.eks_account_id}:role/sys-monitor-cross-account-role"
    }
  }
}

