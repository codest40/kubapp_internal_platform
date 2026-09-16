data "aws_eks_cluster" "this" {
  name = local.cluster_name
}

data "aws_eks_addon_version" "efs" {
  addon_name         = "aws-efs-csi-driver"
  kubernetes_version = data.aws_eks_cluster.this.version
  most_recent        = true
}

resource "kubernetes_storage_class" "efs" {
  metadata {
    name = "efs-sc"
  }

  storage_provisioner = "efs.csi.aws.com"

  parameters = {
    provisioningMode = "efs-ap"
    fileSystemId     = local.efs_id
    directoryPerms   = "777"
    basePath         = "/dynamic_provisioning"

  }

  reclaim_policy         = "Retain"
  volume_binding_mode    = "Immediate"
  allow_volume_expansion = true
}

resource "aws_eks_addon" "efs_csi" {
  cluster_name             = local.cluster_name
  addon_name               = "aws-efs-csi-driver"
  addon_version            = data.aws_eks_addon_version.efs.version
  service_account_role_arn = local.efs_role_arn

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = local.k8s_labels
}

# for prometheus
resource "kubernetes_storage_class" "ebs_gp3" {
  metadata {
    name = "gp3"

    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "false"
    }
  }

  storage_provisioner = "ebs.csi.aws.com"

  volume_binding_mode = "WaitForFirstConsumer"

  parameters = {
    type   = "gp3"
    fsType = "ext4"
  }

  depends_on = [
    aws_eks_addon.ebs_csi
  ]
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name                = local.cluster_name
  addon_name                  = "aws-ebs-csi-driver"
  service_account_role_arn    = local.ebs_csi_irsa_arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}
