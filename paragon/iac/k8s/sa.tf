resource "kubernetes_service_account_v1" "lb_controller" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"

    labels = merge(local.k8s_labels, {
      component = "networking"
      workload  = "load-balancer"
    })

    annotations = {
      "eks.amazonaws.com/role-arn" = local.lb_controller_role_arn
      "trace.aws/role"             = "lb-controller"
      "trace.aws/cluster"          = local.cluster_name
    }
  }
}

resource "kubernetes_service_account_v1" "external_dns" {
  metadata {
    name      = "external-dns"
    namespace = "kube-system"

    labels = merge(local.k8s_labels, {
      component = "networking"
      workload  = "dns"
    })

    annotations = {
      "eks.amazonaws.com/role-arn" = local.external_dns_role_arn
      "trace.aws/role"             = "external-dns"
    }
  }
}

resource "kubernetes_service_account_v1" "fluentbit" {
  metadata {
    name      = "fluent-bit"
    namespace = "kube-system"

    labels = merge(local.k8s_labels, {
      component = "observability"
      workload  = "logging"
      telemetry = "logs"
    })

    annotations = {
      "eks.amazonaws.com/role-arn" = local.fluentbit_role_arn
      "trace.aws/role"             = "fluentbit"
    }
  }
}

