
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

locals {
  kubapp_vpc_id             = data.terraform_remote_state.kubapp_infra.outputs.vpc_id
  kubapp_vpc_cidr           = data.terraform_remote_state.kubapp_infra.outputs.vpc_cidr
  kubapp_private_subnet_ids = data.terraform_remote_state.kubapp_infra.outputs.private_subnet_ids
  kubapp_db_access_sg_id    = data.terraform_remote_state.kubapp_infra.outputs.db_access_security_group_id
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


#############################################
# VPC CONIFGG
######################################
resource "aws_vpc" "sys_monitor" {
  cidr_block           = "10.40.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "sys-monitor-vpc"
  }
}

# KUBAPP VPC PEERING
resource "aws_vpc_peering_connection" "kubapp" {
  vpc_id        = aws_vpc.sys_monitor.id
  peer_vpc_id   = local.kubapp_vpc_id
  peer_owner_id = local.eks_account_id
  peer_region   = var.region

  auto_accept = false
  tags = {
    Name          = "sys-monitor-to-kubapp"
    resource-type = "vpc-peering"
  }
}

resource "aws_route" "kubapp" {
  route_table_id            = aws_route_table.sys_monitor.id
  destination_cidr_block    = local.kubapp_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.kubapp.id
}

resource "aws_internet_gateway" "sys_monitor" {
  vpc_id = aws_vpc.sys_monitor.id

  tags = {
    Name = "sys-monitor-igw"
  }
}

resource "aws_subnet" "sys_monitor" {
  vpc_id                  = aws_vpc.sys_monitor.id
  cidr_block              = "10.40.1.0/24"
  availability_zone       = "${var.region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "sys-monitor-subnet"
  }
}

resource "aws_route_table" "sys_monitor" {
  vpc_id = aws_vpc.sys_monitor.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.sys_monitor.id
  }

  tags = {
    Name = "sys-monitor-route-table"
  }
}

resource "aws_route_table_association" "sys_monitor" {
  subnet_id      = aws_subnet.sys_monitor.id
  route_table_id = aws_route_table.sys_monitor.id
}

###################################################
####  DNS SETUP ####
resource "aws_route53_record" "monitor" {
  provider = aws.cross
  zone_id  = data.aws_route53_zone.sys_monitor.zone_id
  name     = "monitor.${local.domain_name}"
  type     = "A"
  ttl      = 300

  records = [
    aws_eip.sys_monitor.public_ip
  ]
}

resource "aws_route53_record" "grafana" {
  provider = aws.cross
  zone_id  = data.aws_route53_zone.sys_monitor.zone_id
  name     = "graf.${local.domain_name}"
  type     = "A"
  ttl      = 300

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
  zone_id  = data.aws_route53_zone.sys_monitor.zone_id
  name     = "git.${local.domain_name}"
  type     = "A"
  ttl      = 300

  records = [
    aws_eip.sys_monitor.public_ip
  ]
}

resource "aws_route53_record" "codebase" {
  provider = aws.cross
  zone_id  = data.aws_route53_zone.sys_monitor.zone_id
  name     = "codebase.${local.domain_name}"
  type     = "A"
  ttl      = 300

  records = [
    aws_eip.sys_monitor.public_ip
  ]
}

resource "aws_route53_record" "gitops" {
  provider = aws.cross
  zone_id  = data.aws_route53_zone.sys_monitor.zone_id
  name     = "gitops.${local.domain_name}"
  type     = "A"
  ttl      = 300

  records = [
    aws_eip.sys_monitor.public_ip
  ]
}


###########################################
# VPC PEERING OUTPUTS
###########################################

output "sys_monitor_peering_connection_id" {
  description = "VPC peering connection requested by sys_monitor"
  value       = aws_vpc_peering_connection.kubapp.id
}

output "sys_monitor_vpc_id" {
  description = "sys_monitor VPC ID"
  value       = aws_vpc.sys_monitor.id
}

output "sys_monitor_vpc_cidr" {
  description = "CIDR block of the sys_monitor VPC"
  value       = aws_vpc.sys_monitor.cidr_block
}
