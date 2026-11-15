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

provider "aws" {
  alias   = "kubapp"
  region  = var.region
  profile = "database-cross"
  assume_role {
    role_arn = local.kubapp_db_cross_account_role_arn
  }
}

data "terraform_remote_state" "infra" {
  backend = "s3"
  config = {
    bucket  = "kubapp-tf-state-${var.kubapp_account_id}"
    key     = "${var.env}/infra/terraform.tfstate"
    region  = var.region
    profile = "database-cross"
    assume_role = {
      role_arn = local.kubapp_db_cross_account_role_arn
    }
  }
}

provider "aws" {
  alias   = "sys-monitor"
  region  = var.region
  profile = "database-sys-monitor"
  assume_role {
    role_arn = local.sys_monitor_db_bi_directional_role_arn
  }
}

data "terraform_remote_state" "sys_monitor" {
  backend = "s3"
  config = {
    bucket  = "kubapp-sys-monitor-${var.sys_monitor_account_id}"
    key     = "${var.env}/sys-monitor-runtime/tf-state"
    region  = var.region
    profile = "database-sys-monitor"
    assume_role = {
      role_arn = local.sys_monitor_db_bi_directional_role_arn
    }
  }
}
############################
# LOCALS
####################################
locals {
  kubapp_db_cross_account_role_arn           = "arn:aws:iam::${var.kubapp_account_id}:role/db-cross-account-role"
  sys_monitor_database_peering_connection_id = try(data.terraform_remote_state.sys_monitor.outputs.sys_monitor_database_peering_connection_id, null)
  sys_monitor_db_bi_directional_role_arn     = "arn:aws:iam::${var.sys_monitor_account_id}:role/allow-kubapp-read-sys-monitor-state-role"
}

######################################
# VARIABLES
######################################
variable "admin_kubapp_role" {
  type = string
}

variable "admin_github_role" {
  type = string
}

variable "kubapp_db_state_reader" {
  type = string
}

variable "kubapp_db_role_name" {
  type = string
}

variable "sys_monitor_account_id" {
  type = string
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
  count          = 2
  subnet_id      = aws_subnet.database_private[count.index].id
  route_table_id = aws_route_table.database_private.id
}


############################################
# DATABASE SECURITY GROUP
############################################
resource "aws_security_group" "database" {
  name        = "${local.project}-${local.env}-database"
  description = "Security group for KUBAPP cross-account database"
  vpc_id      = aws_vpc.database.id

  # Only RDS Proxy can provide application database access.
  ingress {
    description = "PostgreSQL from RDS Proxy"
    from_port   = local.database_port
    to_port     = local.database_port
    protocol    = "tcp"
    security_groups = [
      aws_security_group.db_proxy.id
    ]
  }

  # sys_monitor access is controlled by shared mode configuration.
  dynamic "ingress" {
    for_each = length(local.sys_monitor_database_cidrs) > 0 ? [1] : []
    content {
      description = "PostgreSQL from sys_monitor"
      from_port   = local.database_port
      to_port     = local.database_port
      protocol    = "tcp"
      cidr_blocks = local.sys_monitor_database_cidrs
    }
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
# SYS_MONITOR VPC PEERING
############################################
resource "aws_vpc_peering_connection_accepter" "sys_monitor" {
  count = local.sys_monitor_enabled && local.sys_monitor_cross_mode_enabled ? 1 : 0

  vpc_peering_connection_id = local.sys_monitor_database_peering_connection_id
  auto_accept               = true
  tags = {
    Name    = "${local.project}-${local.env}-sys-monitor-database"
    project = local.project
    env     = local.env
  }
}

resource "aws_route" "database_to_sys_monitor" {
  count                     = local.sys_monitor_enabled && local.sys_monitor_cross_mode_enabled ? 1 : 0
  route_table_id            = aws_route_table.database_private.id
  destination_cidr_block    = local.sys_monitor_cross_mode_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection_accepter.sys_monitor[0].id
}

############################################
# RDS PROXY SECURITY GROUP
############################################

resource "aws_security_group" "db_proxy" {
  name        = "${local.project}-${local.env}-db-proxy"
  description = "Security group for KUBAPP cross-account RDS Proxy"
  vpc_id      = aws_vpc.database.id

  # Applications connect from the KUBAPP VPC through VPC peering.
  ingress {
    description = "PostgreSQL from KUBAPP VPC"

    from_port = local.database_port
    to_port   = local.database_port
    protocol  = "tcp"

    cidr_blocks = [
      local.kubapp_account_vpc_cidr
    ]
  }

  # sys_monitor access is controlled by shared mode configuration.
  dynamic "ingress" {
    for_each = length(local.sys_monitor_database_cidrs) > 0 ? [1] : []

    content {
      description = "PostgreSQL from sys_monitor"

      from_port = local.database_port
      to_port   = local.database_port
      protocol  = "tcp"

      cidr_blocks = local.sys_monitor_database_cidrs
    }
  }

  # Proxy communicates with PostgreSQL inside the database VPC.
  egress {
    description = "PostgreSQL traffic to database"

    from_port = local.database_port
    to_port   = local.database_port
    protocol  = "tcp"

    cidr_blocks = [
      local.account_vpc_cidr
    ]
  }

  tags = {
    Name    = "${local.project}-${local.env}-db-proxy"
    project = local.project
    env     = local.env
  }
}

############################################
# RDS PROXY SECRET
############################################

resource "aws_secretsmanager_secret" "db_proxy" {
  name = "${local.project}/${local.env}/database/rds-proxy"

  tags = {
    Name    = "${local.project}-${local.env}-db-proxy"
    project = local.project
    env     = local.env
  }
}

resource "aws_secretsmanager_secret_version" "db_proxy" {
  secret_id = aws_secretsmanager_secret.db_proxy.id

  secret_string = jsonencode({
    username = var.master_username
    password = var.master_password
  })
}

############################################
# RDS PROXY IAM ROLE
############################################
resource "aws_iam_role" "db_proxy" {
  name = "${local.project}-${local.env}-db-proxy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"

      Principal = {
        Service = "rds.amazonaws.com"
      }

      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name    = "${local.project}-${local.env}-db-proxy-role"
    project = local.project
    env     = local.env
  }
}

resource "aws_iam_role_policy" "db_proxy" {
  name = "${local.project}-${local.env}-db-proxy-secret-access"
  role = aws_iam_role.db_proxy.id
  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"

      Action = [
        "secretsmanager:GetSecretValue"
      ]

      Resource = aws_secretsmanager_secret.db_proxy.arn
    }]
  })
}

############################################
# RDS PROXY DEFAULT TARGET GROUP
############################################
resource "aws_db_proxy_default_target_group" "database" {
  db_proxy_name = aws_db_proxy.database.name
  connection_pool_config {
    connection_borrow_timeout    = 120
    max_connections_percent      = 90
    max_idle_connections_percent = 50
  }
}

############################################
# RDS PROXY DATABASE TARGET
############################################
resource "aws_db_proxy_target" "database" {
  db_proxy_name          = aws_db_proxy.database.name
  target_group_name      = aws_db_proxy_default_target_group.database.name
  db_instance_identifier = aws_db_instance.database.identifier
}

############################################
# RDS PROXY
############################################
resource "aws_db_proxy" "database" {
  name                   = "${local.project}-${local.env}-proxy"
  engine_family          = "POSTGRESQL"
  debug_logging          = false
  idle_client_timeout    = 1800
  require_tls            = true
  role_arn               = aws_iam_role.db_proxy.arn
  vpc_subnet_ids         = aws_subnet.database_private[*].id
  vpc_security_group_ids = [aws_security_group.db_proxy.id]

  auth {
    auth_scheme               = "SECRETS"
    secret_arn                = aws_secretsmanager_secret.db_proxy.arn
    iam_auth                  = "DISABLED"
    client_password_auth_type = "POSTGRES_SCRAM_SHA_256"
  }

  depends_on = [
    aws_iam_role_policy.db_proxy,
    aws_secretsmanager_secret_version.db_proxy
  ]

  tags = {
    Name    = "${local.project}-${local.env}-proxy"
    project = local.project
    env     = local.env
  }
}

##############################################
# VPC PEERING REQUEST: DB ACCOUNT --> KUBAPP ACCOUNT
############################################
resource "aws_vpc_peering_connection" "kubapp_database" {
  vpc_id        = aws_vpc.database.id
  peer_vpc_id   = local.kubapp_account_vpc_id
  peer_owner_id = local.kubapp_account_id
  auto_accept   = false

  tags = {
    Name    = "${local.project}-${local.env}-kubapp-database"
    project = local.project
    env     = local.env
  }
}


############################################
# DATABASE → KUBAPP ROUTE
############################################

resource "aws_route" "database_to_kubapp" {
  route_table_id            = aws_route_table.database_private.id
  destination_cidr_block    = local.kubapp_account_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.kubapp_database.id
}


### Subnet Group
resource "aws_db_subnet_group" "database" {
  name       = "${local.project}-${local.env}-db"
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

output "database_proxy_endpoint" {
  value = aws_db_proxy.database.endpoint
}

output "database_proxy_security_group_id" {
  value = aws_security_group.db_proxy.id
}

output "database_proxy_arn" {
  value = aws_db_proxy.database.arn
}
