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
  bucket_name = var.bucket_name
  state_key   = "${var.env}/database-assume/tf-state"
}


resource "aws_s3_object" "terraform_state" {
  bucket  = local.bucket_name
  key     = local.state_key
  content = ""
}


