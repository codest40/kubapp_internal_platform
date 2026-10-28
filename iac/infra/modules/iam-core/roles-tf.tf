############################################
# SYS MONITOR TERRAFORM ROLE
############################################

resource "aws_iam_role" "sys_monitor_terraform" {
  name = "sys-monitor-terraform-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          AWS = [
            var.kubapp_account_user_arn,
            var.sys_monitor_account_user_arn
          ]
        }

        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "sys_monitor_terraform" {
  name = "sys-monitor-terraform"
  role = aws_iam_role.sys_monitor_terraform.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "ReadSysMonitorRole"
        Effect = "Allow"
        Action = [
          "iam:GetRole"
        ]
        Resource = "arn:aws:iam::${var.account_id}:role/sys-monitor-ec2-role"
      },
      {
        Sid    = "EC2Infrastructure"
        Effect = "Allow"

        Action = [
          "ec2:DescribeImages",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeInstanceAttribute",
          "ec2:DescribeInstanceCreditSpecifications",
          "ec2:DescribeVpcs",
          "ec2:DescribeSubnets",
          "ec2:DescribeRouteTables",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeInstances",
          "ec2:DescribeTags",
          "ec2:DescribeNetworkInterfaces",

          "ec2:CreateVpc",
          "ec2:DeleteVpc",
          "ec2:ModifyVpcAttribute",

          "ec2:CreateInternetGateway",
          "ec2:AttachInternetGateway",
          "ec2:DetachInternetGateway",
          "ec2:DeleteInternetGateway",

          "ec2:CreateSubnet",
          "ec2:DeleteSubnet",

          "ec2:CreateRouteTable",
          "ec2:DeleteRouteTable",
          "ec2:CreateRoute",
          "ec2:ReplaceRoute",
          "ec2:DeleteRoute",

          "ec2:AssociateRouteTable",
          "ec2:DisassociateRouteTable",

          "ec2:CreateSecurityGroup",
          "ec2:DeleteSecurityGroup",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:AuthorizeSecurityGroupEgress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupEgress",
          "ec2:DescribeSecurityGroupRules",

          "ec2:RunInstances",
          "ec2:TerminateInstances",
          "ec2:StopInstances",
          "ec2:StartInstances",
          "ec2:ModifyInstanceAttribute",

          "ec2:ImportKeyPair",
          "ec2:DeleteKeyPair",
          "ec2:DescribeKeyPairs",

          "ec2:CreateVolume",
          "ec2:DeleteVolume",
          "ec2:AttachVolume",
          "ec2:DetachVolume",
          "ec2:DescribeVolumes",
        ]

        Resource = "*"
      },
      {
        Sid    = "NetworkInterfaceManagement"
        Effect = "Allow"
        Action = [
          "ec2:DescribeNetworkInterfaces"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowResourceTagging"
        Effect = "Allow"
        Action = [
          "ec2:CreateTags",
          "ec2:DeleteTags"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowVPCAttributeRead"
        Effect = "Allow"
        Action = [
          "ec2:DescribeVpcAttribute",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeNetworkInterfaces"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowInternetGatewayRead"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInternetGateways"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowSubnetAttributeManagement"
        Effect = "Allow"
        Action = [
          "ec2:ModifySubnetAttribute"
        ]
        Resource = "*"
      },
      {
        Sid    = "IAMInstanceProfileRead"
        Effect = "Allow"

        Action = [
          "iam:GetInstanceProfile"
        ]

        Resource = "*"
      },

      {
        Sid    = "EKSRead"
        Effect = "Allow"

        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters",
          "eks:AccessKubernetesApi"
        ]

        Resource = "*"
      },

      {
        Sid    = "STSIdentity"
        Effect = "Allow"

        Action = [
          "sts:GetCallerIdentity"
        ]

        Resource = "*"
      },
      {
        Sid    = "AllowSysMonitorEC2RolePass"
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = "arn:aws:iam::${var.account_id}:role/sys-monitor-ec2-role"
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "ec2.amazonaws.com"
          }
        }
      },
      {
        Sid    = "ManageElasticIP"
        Effect = "Allow"
        Action = [
          "ec2:AllocateAddress",
          "ec2:ReleaseAddress",
          "ec2:AssociateAddress",
          "ec2:DisassociateAddress"
        ]
        Resource = "*"
      },
      {
        Sid    = "ReadElasticIPs"
        Effect = "Allow"
        Action = [
          "ec2:DescribeAddresses",
          "ec2:DescribeAddressesAttribute"
        ]
        Resource = "*"
      },
      {
        Sid    = "ReadRoute53HostedZones"
        Effect = "Allow"
        Action = [
          "route53:ListHostedZones",
          "route53:GetChange"
        ]
        Resource = "*"
      },
      {
        Sid    = "ManageSysMonitorDNS"
        Effect = "Allow"
        Action = [
          "route53:GetHostedZone",
          "route53:ListTagsForResource",
          "route53:ChangeResourceRecordSets",
          "route53:ListResourceRecordSets"
        ]
        Resource = "arn:aws:route53:::hostedzone/${var.zone_id}"
      },

      {
        Sid    = "AllowSysMonitorEC2RolePolicy"
        Effect = "Allow"
        Action = [
          "iam:GetRole",
          "iam:PutRolePolicy",
          "iam:GetRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:ListRolePolicies"
        ]
        Resource = "arn:aws:iam::${var.account_id}:role/sys-monitor-ec2-role"
      }
    ]
  })
}
