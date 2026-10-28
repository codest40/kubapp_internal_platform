############################################
# EKS CLUSTER ROLE
############################################
resource "aws_iam_role" "eks_cluster" {
  name = "${var.cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "eks_vpc_resource_controller" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
}

############################################
# NODE GROUP ROLE
############################################
resource "aws_iam_role" "node_group" {
  name = "${var.cluster_name}-nodegroup-role"

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

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "node_worker" {
  role       = aws_iam_role.node_group.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  role       = aws_iam_role.node_group.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr" {
  role       = aws_iam_role.node_group.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

############################################
# FARGATE ROLE
############################################
resource "aws_iam_role" "fargate" {
  name = "${var.cluster_name}-fargate-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "eks-fargate-pods.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "fargate_attach" {
  role       = aws_iam_role.fargate.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
}

resource "aws_iam_policy" "fargate_cloudwatch_logs" {
  name = "${var.cluster_name}-fargate-cloudwatch-logs"

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]

        Resource = "${var.fargate_log_group_arn}:*"
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "fargate_cloudwatch_logs" {
  role       = aws_iam_role.fargate.name
  policy_arn = aws_iam_policy.fargate_cloudwatch_logs.arn
}

############################################
# SYSTEM MONITOR EC2 ROLE
############################################
resource "aws_iam_role" "ec2_role" {
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
  user = var.kubapp_account_user
  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect   = "Allow"
      Action   = "sts:AssumeRole"
      Resource = aws_iam_role.ec2_role.arn
    }]
  })
}

resource "aws_iam_role_policy" "eks_access" {
  name = "sys-monitor-eks-access"
  role = aws_iam_role.ec2_role.id

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
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# INSTANCE PROFILE
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "sys-monitor-ec2-profile"
  role = aws_iam_role.ec2_role.name
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
          "arn:aws:s3:::${var.tf_state_bucket}/*"
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

