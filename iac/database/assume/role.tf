resource "aws_iam_role" "db_terraform" {
  name = "db-terraform-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"

      Principal = {
        AWS = [local.db_user_arn, local.github_role_arn]
      }

      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    project = "kubapp"
    purpose = "database-terraform"
  }
}

resource "aws_iam_role_policy" "db_terraform" {
  role = aws_iam_role.db_terraform.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "DatabaseInfrastructure"
        Effect = "Allow"

        Action = [
          "ec2:*",
          "rds:*"
        ]

        Resource = "*"
      },

      {
        Sid    = "CloudWatch"
        Effect = "Allow"

        Action = [
          "cloudwatch:*",
          "logs:*"
        ]

        Resource = "*"
      },

      {
        Sid    = "AssumeKubappDatabaseRole"
        Effect = "Allow"

        Action = [
          "sts:AssumeRole"
        ]

        Resource = local.kubapp_db_cross_account_role_arn
      }
    ]
  })
}
