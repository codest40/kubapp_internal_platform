resource "kubernetes_namespace_v1" "this" {
  for_each = local.namespaces

  metadata {
    name = each.key

    labels = merge(
      local.k8s_labels,

      {
        component = each.value.component
        workload  = each.value.workload
      },

      each.value.labels,

      {
        namespace = each.key
      }
    )
  }
}
