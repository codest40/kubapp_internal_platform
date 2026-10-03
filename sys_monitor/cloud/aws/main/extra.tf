
resource "aws_iam_role_policy" "github_deploy_key" {
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
    }]
  })

  depends_on = [
    data.aws_iam_role.sys_monitor
  ]
}
