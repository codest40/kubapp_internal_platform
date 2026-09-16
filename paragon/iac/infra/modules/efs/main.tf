resource "aws_security_group" "efs" {
  name        = "${var.name_prefix}-efs-sg"
  description = "Allow NFS access to EFS"
  vpc_id      = var.vpc_id

  ingress {
    description = "NFS"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = merge(var.tags, {
    resource-type = "security-group"
    sg-scope      = "storage"
    cluster       = var.cluster_name
    eni-cluster   = var.cluster_name
    workload-type = "efs"
  })
}

resource "aws_efs_file_system" "this" {
  creation_token = "${var.name_prefix}-efs"
  encrypted      = true
  tags = merge(var.tags, {
    name          = "${var.name_prefix}-efs"
    resource-type = "efs"
    cluster       = var.cluster_name
    eni-cluster   = var.cluster_name
    storage-type  = "shared-persistent-volume"
  })
}

resource "aws_efs_mount_target" "this" {
  for_each = {
    for idx, subnet in var.subnet_ids : idx => subnet
  }

  file_system_id  = aws_efs_file_system.this.id
  subnet_id       = each.value
  security_groups = [aws_security_group.efs.id]
}
