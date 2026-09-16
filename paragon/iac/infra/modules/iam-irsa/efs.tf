
resource "aws_iam_role" "efs_csi_role" {
  name = "${var.cluster_name}-efs-csi-driver-role"

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
            "${local.oidc_provider}:sub" = "system:serviceaccount:kube-system:efs-csi-*"
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

resource "aws_iam_role_policy_attachment" "efs_csi_attach" {
  role       = aws_iam_role.efs_csi_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"
}


