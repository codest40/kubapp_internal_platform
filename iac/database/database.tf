############################################
# POSTGRESQL DATABASE
############################################

resource "aws_db_instance" "database" {
  identifier = "${local.project}-${local.env}-database"

  engine         = "postgres"
  engine_version = var.engine_version

  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = var.storage_type
  iops                  = var.iops
  storage_throughput    = var.storage_throughput

  storage_encrypted = local.storage_encrypted

  db_name  = var.database_name
  username = var.master_username
  password = var.master_password

  port = local.database_port

  db_subnet_group_name   = aws_db_subnet_group.database.name
  vpc_security_group_ids = [aws_security_group.database.id]

  multi_az = local.multi_az

  backup_retention_period = var.backup_retention_period
  backup_window           = var.backup_window

  maintenance_window = var.maintenance_window

  deletion_protection = local.deletion_protection
  skip_final_snapshot = local.skip_final_snapshot

  publicly_accessible = false

  auto_minor_version_upgrade = true

  copy_tags_to_snapshot = true

  tags = {
    Name    = "${local.project}-${local.env}-database"
    project = local.project
    env     = local.env
  }
}
