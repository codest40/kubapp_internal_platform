
data "terraform_remote_state" "infra" {
  backend = "s3"

  config = {
    bucket = "kubapp-tf-state-${var.account_id}"
    key    = "${var.env}/k8s/terraform.tfstate"
    region = var.region
  }
}

locals {
  env              = try(data.terraform_remote_state.infra.outputs.env, var.env)
  cluster_name     = try(data.terraform_remote_state.infra.outputs.cluster_name, "${var.project}-${var.env}")
  cluster_endpoint = data.terraform_remote_state.infra.outputs.cluster_endpoint
  cluster_ca_cert  = data.terraform_remote_state.infra.outputs.cluster_ca_certificate

  name_prefix = "kubapp-${var.env}"
}

