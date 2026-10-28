############################################
# CONFIG
############################################

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

data "terraform_remote_state" "infra" {
  backend = "s3"

  config = {
    bucket = "kubapp-tf-state-${var.kubapp_account_id}"
    key    = "${var.env}/infra/terraform.tfstate"
    region = var.region

    assume_role = {
      role_arn = var.kubapp_db_cross_account_role_arn
    }
  }
}


############################################
# DATABASE VPC
############################################

resource "aws_vpc" "database" {
  cidr_block           = local.account_vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name    = "${local.project}-${local.env}-database-vpc"
    project = local.project
    env     = local.env
  }
}


############################################
# DATABASE AVAILABILITY ZONES
############################################

data "aws_availability_zones" "available" {
  state = "available"
}


############################################
# DATABASE PRIVATE SUBNETS
############################################

resource "aws_subnet" "database_private" {
  count = 2

  vpc_id = aws_vpc.database.id

  cidr_block = cidrsubnet(
    local.account_vpc_cidr,
    8,
    count.index + 1
  )

  availability_zone = (
    data.aws_availability_zones.available.names[count.index]
  )

  map_public_ip_on_launch = false

  tags = {
    Name    = "${local.project}-${local.env}-database-private-${count.index + 1}"
    project = local.project
    env     = local.env
  }
}


############################################
# DATABASE ROUTE TABLE
############################################

resource "aws_route_table" "database_private" {
  vpc_id = aws_vpc.database.id

  tags = {
    Name    = "${local.project}-${local.env}-database-private"
    project = local.project
    env     = local.env
  }
}


############################################
# DATABASE ROUTE TABLE ASSOCIATIONS
############################################

resource "aws_route_table_association" "database_private" {
  count = 2

  subnet_id = aws_subnet.database_private[count.index].id

  route_table_id = aws_route_table.database_private.id
}


############################################
# DATABASE SECURITY GROUP
############################################

resource "aws_security_group" "database" {
  name        = "${local.project}-${local.env}-database"
  description = "Security group for KUBAPP cross-account database"
  vpc_id      = aws_vpc.database.id

  ingress {
    description = "PostgreSQL from KUBAPP VPC"

    from_port = local.database_port
    to_port   = local.database_port
    protocol  = "tcp"

    cidr_blocks = [
      local.kubapp_account_vpc_cidr
    ]
  }

  egress {
    description = "Database outbound traffic"

    from_port = 0
    to_port   = 0
    protocol  = "-1"

    cidr_blocks = [
      "0.0.0.0/0"
    ]
  }

  tags = {
    Name    = "${local.project}-${local.env}-database"
    project = local.project
    env     = local.env
  }
}


############################################
# VPC PEERING REQUEST
#
# DATABASE ACCOUNT
#     ↓
# KUBAPP ACCOUNT
############################################

resource "aws_vpc_peering_connection" "kubapp_database" {
  vpc_id = aws_vpc.database.id

  peer_vpc_id = local.kubapp_account_vpc_id

  peer_owner_id = local.kubapp_account_id

  auto_accept = false

  tags = {
    Name    = "${local.project}-${local.env}-kubapp-database"
    project = local.project
    env     = local.env
  }
}


############################################
# DATABASE → KUBAPP ROUTE
#
# This becomes usable after KUBAPP accepts
# the peering request.
############################################

resource "aws_route" "database_to_kubapp" {
  route_table_id = aws_route_table.database_private.id
  destination_cidr_block = local.kubapp_account_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.kubapp_database.id
}


### Subnet Group
resource "aws_db_subnet_group" "database" {
  name = "${local.project}-${local.env}-db"

  subnet_ids = aws_subnet.database_private[*].id

  tags = {
    Name    = "${local.project}-${local.env}-db"
    project = local.project
    env     = local.env
  }
}

############################################
# OUTPUTS
############################################

output "database_vpc_id" {
  value = aws_vpc.database.id
}

output "database_vpc_cidr" {
  value = local.account_vpc_cidr
}

output "database_private_subnet_ids" {
  value = aws_subnet.database_private[*].id
}

output "database_security_group_id" {
  value = aws_security_group.database.id
}

output "database_peering_connection_id" {
  value = aws_vpc_peering_connection.kubapp_database.id
}

