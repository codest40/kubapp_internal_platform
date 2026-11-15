
############################################
# SYSTEM MONITOR EC2 ROLE
############################################
resource "aws_iam_role" "ec2_role" {
  count = var.sys_monitor_enabled ? 1 : 0

  name = "sys-monitor-ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      },
      {
        Effect = "Allow"
        Principal = {
          AWS = var.kubapp_account_user_arn
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_user_policy" "user_assume_sys_monitor" {
  count = var.sys_monitor_enabled ? 1 : 0
  user  = var.kubapp_account_user
  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect   = "Allow"
      Action   = "sts:AssumeRole"
      Resource = aws_iam_role.ec2_role[0].arn
    }]
  })
}

resource "aws_iam_role_policy" "eks_access" {
  count = var.sys_monitor_enabled ? 1 : 0

  name = "sys-monitor-eks-access"
  role = aws_iam_role.ec2_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEKSDescribe"
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters",
          "eks:AccessKubernetesApi"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowSTSIdentity"
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  count      = var.sys_monitor_enabled ? 1 : 0
  role       = aws_iam_role.ec2_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# INSTANCE PROFILE
resource "aws_iam_instance_profile" "ec2_profile" {
  count = var.sys_monitor_enabled ? 1 : 0

  name = "sys-monitor-ec2-profile"
  role = aws_iam_role.ec2_role[0].name
}

###################3#######
# CROSS ACCOUNR ROLE
################################
resource "aws_iam_role" "sys_monitor_cross_account_role" {
  count = var.enable_cross_account ? 1 : 0
  name  = "sys-monitor-cross-account-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = [var.cross_account_role_arn, var.sys_monitor_account_user_arn]
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "cross_account_policy" {
  count = var.enable_cross_account ? 1 : 0

  role = aws_iam_role.sys_monitor_cross_account_role[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [

      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters",
          "eks:AccessKubernetesApi"
        ]
        Resource = "*"
      },

      # S3 access
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.tf_state_bucket}",
          "arn:aws:s3:::${var.tf_state_bucket}/*",
          "arn:aws:s3:::${var.db_state_bucket}",
          "arn:aws:s3:::${var.db_state_bucket}/*",
        ]
      },

      # Route53
      {
        Effect = "Allow"
        Action = [
          "route53:ListHostedZones",
          "route53:ListResourceRecordSets"
        ]
        Resource = "*"
      }
    ]
  })
}

######################
# DATABASE ROLE
###############################
resource "aws_iam_role" "db_cross_account_role" {
  count = var.enable_db_cross_account ? 1 : 0

  name = "db-cross-account-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = [var.database_account_arn, var.admin_github_arn]
        #var.visitor_account_user_arn
      }
      Action = "sts:AssumeRole"
    }]
  })
  tags = var.tags
}

locals {
  visitor_account_user = split("/", var.visitor_account_user_arn)[1]
}

resource "aws_iam_user_policy" "admin_assume_db_state_role" {
  count = var.enable_db_cross_account ? 1 : 0
  user  = local.visitor_account_user

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"

      Action   = "sts:AssumeRole"
      Resource = aws_iam_role.db_cross_account_role[0].arn
    }]
  })
}

resource "aws_iam_role_policy" "db_cross_account_state" {
  count = var.enable_db_cross_account ? 1 : 0

  name = "db-cross-account-state-read"
  role = aws_iam_role.db_cross_account_role[0].id
  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject"
      ]
      Resource = [
        "arn:aws:s3:::${var.tf_state_bucket}",
        "arn:aws:s3:::${var.tf_state_bucket}/*"
      ]
    }]
  })
}

