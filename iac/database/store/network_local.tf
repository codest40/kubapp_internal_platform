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
  }
}


############################################
# DATABASE SUBNET GROUP
############################################

resource "aws_db_subnet_group" "database" {
  name = "${local.project}-${local.env}-db"

  subnet_ids = (
    data.terraform_remote_state.infra.outputs.private_subnet_ids
  )

  tags = {
    Name    = "${local.project}-${local.env}-db"
    project = local.project
    env     = local.env
  }
}


############################################
# DATABASE SECURITY GROUP
############################################

resource "aws_security_group" "database" {
  name        = "${local.project}-${local.env}-database"
  description = "Security group for KUBAPP database"
  vpc_id      = local.kubapp_account_vpc_id

  ingress {
    description     = "PostgreSQL from application data boundary"
    from_port       = local.database_port
    to_port         = local.database_port
    protocol        = "tcp"
    security_groups = [local.sg_boundary_id]
  }

  egress {
    description = "Database outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${local.project}-${local.env}-database"
    project = local.project
    env     = local.env
  }
}

############################################
# OUTPUTS
############################################

output "database_vpc_id" {
  value = local.kubapp_account_vpc_id
}

output "database_vpc_cidr" {
  value = local.kubapp_account_vpc_cidr
}

output "database_private_subnet_ids" {
  value = data.terraform_remote_state.infra.outputs.private_subnet_ids
}

output "database_security_group_id" {
  value = aws_security_group.database.id
}

output "database_peering_connection_id" {
  value = null
}
