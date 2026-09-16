
output "namespaces" {
  value = [
    for ns in kubernetes_namespace_v1.this : ns.metadata[0].name
  ]
}

output "full_namespaces" {
  value = {
    for k, ns in kubernetes_namespace_v1.this :
    k => {
      name   = ns.metadata[0].name
      labels = ns.metadata[0].labels

      component = local.namespaces[k].component
      workload  = local.namespaces[k].workload
      #env       = var.env
    }
  }
}

output "cluster_name" {
  value = local.cluster_name
}

output "cluster_endpoint" {
  value = local.cluster_endpoint
}

output "cluster_ca_certificate" {
  value = local.cluster_ca_cert
}

output "Environment" {
  value = local.env
}

output "domain" {
  value = local.main_domain
}
