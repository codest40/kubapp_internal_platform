locals {
  secret_path = "${path.root}/../../gitops/secrets"
}

resource "null_resource" "apply_secrets" {
  triggers = {
    secrets_dir = sha256(join("", [
      for file in fileset(local.secret_path, "**/*.yaml") :
      filesha256("${local.secret_path}/${file}")
    ]))
  }

  provisioner "local-exec" {
    command = "python3 ${path.root}/../../scripts/gitops/apply_secrets.py"
  }

  depends_on = [
    kubernetes_namespace_v1.this["argocd"],
    kubernetes_namespace_v1.this["monitoring"]
  ]
}
