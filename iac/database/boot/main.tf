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
  bucket_name = "kubapp-database-tf-state-${var.account_id}"
  state_key   = "${var.env}/database/tf-state"
}


############################################
# TERRAFORM STATE BUCKET
############################################

resource "aws_s3_bucket" "terraform_state" {
  bucket        = local.bucket_name
  force_destroy = true

  tags = {
    Name    = local.bucket_name
    project = "kubapp"
    purpose = "database-terraform-state"
    env     = var.env
  }
}


############################################
# VERSIONING
############################################

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}


############################################
# ENCRYPTION
############################################

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}


############################################
# PUBLIC ACCESS BLOCK
############################################

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
