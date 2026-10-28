resource "kubernetes_cluster_role_v1" "sys_monitor_gitops" {
  metadata {
    name = "sys-monitor-gitops"
  }

  rule {
    api_groups = ["argoproj.io"]
    resources  = ["applications"]
    verbs      = ["list"]
  }

  rule {
    api_groups = [""]
    resources  = ["nodes"]
    verbs      = ["list"]
  }

  rule {
    api_groups = [""]
    resources  = ["pods"]
    verbs      = ["list"]
  }

}

resource "kubernetes_cluster_role_binding_v1" "sys_monitor_gitops" {
  metadata {
    name = local.sys_monitor_rbac_name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.sys_monitor_gitops.metadata[0].name
  }

  subject {
    kind      = "Group"
    name      = local.sys_monitor_rbac_name
    api_group = "rbac.authorization.k8s.io"
  }
}
