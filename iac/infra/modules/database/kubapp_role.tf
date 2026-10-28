############################################
# KUBAPP CALLS DB STATE BUCKET
############################################
locals {
  admin_user = split("/", var.admin_kubapp_arn)[1]
}

resource "aws_iam_user_policy" "admin_assume_db_state_role" {
  user = local.admin_user

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"

      Action   = "sts:AssumeRole"
      Resource = aws_iam_role.kubapp_db_state_reader.arn
    }]
  })
}

resource "aws_iam_role" "kubapp_db_state_reader" {
  name = "kubapp-reads-db-state-role"

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
    purpose = "database-state-access"
  })
}

resource "aws_iam_role_policy" "kubapp_db_state_assume" {
  role = aws_iam_role.kubapp_db_state_reader.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"

      Action   = "sts:AssumeRole"
      Resource = "arn:aws:iam::${var.database_account_id}:role/db-lets-kubapp-read-state-role"
    }]
  })
}

