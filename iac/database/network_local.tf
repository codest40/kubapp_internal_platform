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
    description     = "PostgreSQL from RDS Proxy"
    from_port       = local.database_port
    to_port         = local.database_port
    protocol        = "tcp"
    security_groups = [aws_security_group.db_proxy.id]
  }

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
# RDS PROXY SECURITY GROUP
############################################

resource "aws_security_group" "db_proxy" {
  name        = "${local.project}-${local.env}-db-proxy"
  description = "Security group for KUBAPP RDS Proxy"
  vpc_id      = local.kubapp_account_vpc_id

  # Application workloads connect through db_access.
  ingress {
    description     = "PostgreSQL from DB_ACCESS sg application data boundary"
    from_port       = local.database_port
    to_port         = local.database_port
    protocol        = "tcp"
    security_groups = [local.sg_boundary_id, local.ec2_node_sg_id]
  }

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
  # Proxy connects to PostgreSQL inside the KUBAPP VPC.
  egress {
    description = "PostgreSQL traffic to database"
    from_port   = local.database_port
    to_port     = local.database_port
    protocol    = "tcp"
    cidr_blocks = [local.kubapp_account_vpc_cidr]
  }

  tags = {
    Name    = "${local.project}-${local.env}-db-proxy"
    project = local.project
    env     = local.env
  }
}

############################################
# RDS PROXY DATABASE CREDENTIALS
############################################

resource "aws_secretsmanager_secret" "database_proxy" {
  name        = "${local.project}/${local.env}/database/rds-proxy"
  description = "Database credentials used by KUBAPP RDS Proxy"

  tags = {
    Name    = "${local.project}-${local.env}-db-proxy"
    project = local.project
    env     = local.env
  }
}

resource "aws_secretsmanager_secret_version" "database_proxy" {
  secret_id = aws_secretsmanager_secret.database_proxy.id
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

resource "aws_iam_role_policy" "db_proxy_secrets" {
  name = "${local.project}-${local.env}-db-proxy-secrets"
  role = aws_iam_role.db_proxy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"

      Action = [
        "secretsmanager:GetSecretValue"
      ]
      Resource = aws_secretsmanager_secret.database_proxy.arn
    }]
  })
}

############################################
# RDS PROXY
############################################

resource "aws_db_proxy" "database" {
  name                = "${local.project}-${local.env}-proxy"
  engine_family       = "POSTGRESQL"
  debug_logging       = false
  idle_client_timeout = 1800
  require_tls         = true

  role_arn = aws_iam_role.db_proxy.arn
  vpc_subnet_ids = (
    data.terraform_remote_state.infra.outputs.rds_proxy_private_subnet_ids
  )

  vpc_security_group_ids = [
    aws_security_group.db_proxy.id
  ]

  auth {
    auth_scheme = "SECRETS"
    secret_arn  = aws_secretsmanager_secret.database_proxy.arn
    iam_auth    = "DISABLED"
  }
  depends_on = [
    aws_iam_role_policy.db_proxy_secrets,
    aws_secretsmanager_secret_version.database_proxy
  ]
  tags = {
    Name    = "${local.project}-${local.env}-proxy"
    project = local.project
    env     = local.env
  }
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
  lifecycle {
    replace_triggered_by = [
      aws_db_proxy.database.id
    ]
  }
}

############################################
# RDS PROXY TARGET
############################################
resource "aws_db_proxy_target" "database" {
  db_proxy_name          = aws_db_proxy.database.name
  target_group_name      = aws_db_proxy_default_target_group.database.name
  db_instance_identifier = aws_db_instance.database.identifier

  lifecycle {
    replace_triggered_by = [
      aws_db_proxy.database.id
    ]
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

output "database_proxy_endpoint" {
  description = "KUBAPP PostgreSQL RDS Proxy endpoint"
  value       = aws_db_proxy.database.endpoint
}

output "database_proxy_security_group_id" {
  description = "Security group attached to KUBAPP RDS Proxy"
  value       = aws_security_group.db_proxy.id
}

output "database_proxy_arn" {
  description = "KUBAPP RDS Proxy ARN"
  value       = aws_db_proxy.database.arn
}

