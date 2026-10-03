
data "terraform_remote_state" "kubapp_infra" {
  backend = "s3"

  config = {
    bucket = "kubapp-tf-state-${local.eks_account_id}"
    key    = "${var.env}/infra/terraform.tfstate"
    region = var.region

    profile = "sys-monitor"
    assume_role = {
      role_arn = "arn:aws:iam::${local.eks_account_id}:role/sys-monitor-cross-account-role"
    }
  }
}

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
  region  = var.region
  profile = var.profile
}

provider "aws" {
  alias   = "cross"
  region  = var.region
  profile = var.profile

  assume_role {
    role_arn = "arn:aws:iam::${local.eks_account_id}:role/sys-monitor-terraform-role"
  }
}

data "aws_route53_zone" "sys_monitor" {
  provider     = aws.cross
  name         = "${local.domain_name}."
  private_zone = false
}


####  DNS ####
resource "aws_route53_record" "grafana" {
  provider = aws.cross
  zone_id = data.aws_route53_zone.sys_monitor.zone_id
  name    = "graf.${local.domain_name}"
  type    = "A"
  ttl     = 300

  records = [
    aws_eip.sys_monitor.public_ip
  ]
}

resource "aws_route53_record" "prometheus" {
  provider = aws.cross

  zone_id = data.aws_route53_zone.sys_monitor.zone_id
  name    = "prom.${local.domain_name}"
  type    = "A"
  ttl     = 300

  records = [
    aws_eip.sys_monitor.public_ip
  ]
}

resource "aws_route53_record" "github" {
  provider = aws.cross
  zone_id = data.aws_route53_zone.sys_monitor.zone_id
  name    = "git.${local.domain_name}"
  type    = "A"
  ttl     = 300

  records = [
    aws_eip.sys_monitor.public_ip
  ]
}

resource "aws_route53_record" "codebase" {
  provider = aws.cross
  zone_id = data.aws_route53_zone.sys_monitor.zone_id
  name    = "codebase.${local.domain_name}"
  type    = "A"
  ttl     = 300

  records = [
    aws_eip.sys_monitor.public_ip
  ]
}

resource "aws_route53_record" "gitops" {
  provider = aws.cross
  zone_id = data.aws_route53_zone.sys_monitor.zone_id
  name    = "gitops.${local.domain_name}"
  type    = "A"
  ttl     = 300

  records = [
    aws_eip.sys_monitor.public_ip
  ]
}

