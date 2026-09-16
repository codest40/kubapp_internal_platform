
resource "aws_iam_role" "ebs_csi_irsa" {
  name = "${var.cluster_name}-ebs-csi-irsa"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_provider}:sub" = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
          "${local.oidc_provider}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}


resource "aws_iam_role_policy_attachment" "ebs_csi_irsa_attach" {
  role       = aws_iam_role.ebs_csi_irsa.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}


#resource "aws_eks_addon" "ebs_csi" {
#  cluster_name = var.cluster_name
#  addon_name = "aws-ebs-csi-driver"
#  service_account_role_arn = aws_iam_role.ebs_csi_irsa.arn
#  resolve_conflicts_on_create = "OVERWRITE"
#  resolve_conflicts_on_update = "OVERWRITE"
#  depends_on = [
#    aws_iam_role_policy_attachment.ebs_csi_irsa_attach
#  ]
#}

