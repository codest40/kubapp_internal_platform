locals {
  admin_user = split("/", var.admin_kubapp_arn)[1]
}

resource "aws_iam_user_policy" "admin_assume_sys_monitor_state_role" {
  user = local.admin_user

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"

      Action   = "sts:AssumeRole"
      Resource = aws_iam_role.kubapp_sys_monitor_state_reader.arn
    }]
  })
}

resource "aws_iam_role" "kubapp_sys_monitor_state_reader" {
  name = "kubapp-reads-sys-monitor-state-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"

      Principal = {
        AWS = [var.admin_kubapp_arn, var.admin_github_arn]
      }

      Action = "sts:AssumeRole"
    }]
  })

  tags = merge(var.tags, {
    purpose = "sys-monitor-state-access"
  })
}

resource "aws_iam_role_policy" "kubapp_sys_monitor_state_assume" {
  role = aws_iam_role.kubapp_sys_monitor_state_reader.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"

      Action   = "sts:AssumeRole"
      Resource = var.sys_monitor_state_reader_role_arn
    }]
  })
}
