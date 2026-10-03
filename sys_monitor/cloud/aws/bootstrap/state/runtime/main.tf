terraform {
  required_version = "~> 1.14"

  backend "local" {}
}

provider "aws" {
  region = var.region
}

resource "aws_s3_object" "state" {
  bucket = var.bucket
  key    = "${var.env}/sys-monitor-runtime/tf-state"
}

variable "bucket" {
  type = string
}

variable "env" {
  type = string
}

variable "region" {
  type    = string
  default = "us-east-1"
}

output "bucket" {
  value = var.bucket
}

output "state_key" {
  value = aws_s3_object.state.key
}

output "region" {
  value = var.region
}
