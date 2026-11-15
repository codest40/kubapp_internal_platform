variable "backend_env" {
  description = "Backend environment configuration for sys_monitor."
  type        = string
  sensitive   = true
}

variable "github_deploy_key" {
  description = "Private SSH key used by sys_monitor to clone the repository."
  type        = string
  sensitive   = true
}

resource "aws_ssm_parameter" "backend_env" {
  name        = "/sys-monitor/backend/env"
  description = "Backend environment configuration for sys_monitor."
  type        = "SecureString"
  value       = var.backend_env

  tags = {
    Name        = "sys-monitor-backend-env"
    Environment = var.env
    ManagedBy   = "Terraform"
  }
}

resource "aws_ssm_parameter" "github_deploy_key" {
  name        = "/sys-monitor/github/deploy-key"
  description = "GitHub repository deploy key for sys_monitor."
  type        = "SecureString"
  value       = var.github_deploy_key

  tags = {
    Name        = "sys-monitor-github-deploy-key"
    Environment = var.env
    ManagedBy   = "Terraform"
  }
}

resource "aws_iam_role_policy" "github_deploy_key" {
  name = "sys-monitor-parameter-store-access"
  role = data.aws_iam_role.sys_monitor.name

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Sid    = "ReadGitHubDeployKey"
      Effect = "Allow"

      Action = [
        "ssm:GetParameter"
      ]

      Resource = "arn:aws:ssm:${var.region}:${var.account_id}:parameter/sys-monitor/github/deploy-key"
      },
      {
        Sid    = "ReadBackendEnvironment"
        Effect = "Allow"

        Action = [
          "ssm:GetParameter"
        ]
        Resource = "arn:aws:ssm:${var.region}:${var.account_id}:parameter/sys-monitor/backend/env"
      }
    ]
  })

  depends_on = [
    data.aws_iam_role.sys_monitor
  ]
}
