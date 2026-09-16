
resource "aws_efs_access_point" "this" {
  for_each = var.efs_access_points

  file_system_id = aws_efs_file_system.this.id

  posix_user {
    uid = each.value.uid
    gid = each.value.gid
  }

  root_directory {
    path = each.value.path

    creation_info {
      owner_uid   = each.value.uid
      owner_gid   = each.value.gid
      permissions = "750"
    }
  }

  tags = merge(var.tags, {
    resource-type = "efs-access-point"

    cluster       = var.cluster_name
    eni-cluster   = var.cluster_name

    workload-type = each.key
    storage-path  = each.value.path
  })
}

