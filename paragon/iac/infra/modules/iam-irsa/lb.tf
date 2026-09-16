############################################
# LOAD BALANCER CONTROLLER POLICY
############################################
locals {
  lb_policy = file("${path.module}/policies/iam_policy.json")
}

resource "aws_iam_policy" "lb_controller" {
  name   = "${var.cluster_name}-lb-controller-policy"
  policy = local.lb_policy

  lifecycle {
    create_before_destroy = true
  }

  tags = var.tags
}

############################################
# ASSUME ROLE POLICY (IRSA via OIDC)
############################################
data "aws_iam_policy_document" "lb_controller_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    ############################################
    # MATCHeS SERVICE ACCOUNT
    ############################################
    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_provider_url, "https://", "")}:sub"
      values = [
        "system:serviceaccount:kube-system:aws-load-balancer-controller"
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_provider_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

############################################
# IAM ROLE FOR LB CONTROLLER
############################################
resource "aws_iam_role" "lb_controller" {
  name               = "${var.cluster_name}-lb-controller-role"
  assume_role_policy = data.aws_iam_policy_document.lb_controller_assume_role.json

  tags = var.tags
}

############################################
# ATTACH POLICY
############################################
resource "aws_iam_role_policy_attachment" "lb_controller_attach" {
  role       = aws_iam_role.lb_controller.name
  policy_arn = aws_iam_policy.lb_controller.arn
}
