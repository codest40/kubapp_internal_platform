
resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = var.cluster_role_arn

  version = var.kubernetes_version

  vpc_config {
    subnet_ids = var.private_subnet_ids

    security_group_ids = [
      var.sg_ids["ec2_app"],
      var.sg_ids["fargate_app"]
    ]

    endpoint_private_access = true
    endpoint_public_access  = true
  }

  access_config {
    authentication_mode = "API_AND_CONFIG_MAP"
  }

  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  tags = merge(var.tags, {
    Name          = var.cluster_name
    resource-type = "eks-cluster"

    cluster-role    = "control-plane"
    eks-scope       = "cluster"
    networking-mode = "vpc-native"
  })
}

############################################
# OIDC PROVIDER (REQUIRED FOR IRSA)
############################################

data "tls_certificate" "eks" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "this" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer

  client_id_list = ["sts.amazonaws.com"]

  thumbprint_list = [
    data.tls_certificate.eks.certificates[0].sha1_fingerprint
  ]

  tags = merge(var.tags, {
    resource-type = "iam-oidc-provider"
    layer         = "identity"
    eks-related   = "true"
  })
}


