
resource "aws_iam_role" "app_pods" {
  name = "${var.cluster_name}-app-pods-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Federated = var.oidc_provider_arn
        }

        Action = "sts:AssumeRoleWithWebIdentity"

        Condition = {
          StringLike = {
            "${local.oidc_provider}:sub" = [
              "system:serviceaccount:dev:*",
              "system:serviceaccount:prod:*"
            ]
          }

          StringEquals = {
            "${local.oidc_provider}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = var.tags
}

# SHARED APP RUNTIME POLICY
resource "aws_iam_policy" "app_pods_readonly" {
  name = "${var.cluster_name}-app-pods-readonly-policy"

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [

      # CLOUDWATCH READ
      {
        Effect = "Allow"

        Action = [
          "cloudwatch:GetMetricData",
          "cloudwatch:ListMetrics"
        ]

        Resource = "*"
      },

      # CLOUDWATCH LOGS READ
      {
        Effect = "Allow"

        Action = [
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:GetLogEvents"
        ]

        Resource = "*"
      },

      # S3 READ ONLY
      {
        Effect = "Allow"

        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]

        Resource = "*"
      }
    ]
  })

  tags = var.tags
}


# ATTACH POLICY
resource "aws_iam_role_policy_attachment" "app_pods" {
  role       = aws_iam_role.app_pods.name
  policy_arn = aws_iam_policy.app_pods_readonly.arn
}

