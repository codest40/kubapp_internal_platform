resource "aws_iam_role" "sys_monitor_local_role" {
  name = "sys-monitor-local-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "cross_assume" {
  role = aws_iam_role.sys_monitor_local_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sts:AssumeRole"
      Resource = "arn:aws:iam::${var.eks_account_id}:role/sys-monitor-cross-account-role"
    }]
  })
}

resource "aws_iam_instance_profile" "sys_monitor_local_profile" {
  name = "sys-monitor-local-ec2-profile"
  role = aws_iam_role.sys_monitor_local_role.name
}


