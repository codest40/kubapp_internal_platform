
data "terraform_remote_state" "infra" {
  backend = "s3"
  config = {
    bucket = "kubapp-tf-state-${var.account_id}"
    key    = "${var.env}/infra/terraform.tfstate"
    region = var.region
  }
}

locals {
  env                    = try(data.terraform_remote_state.infra.outputs.env, var.env)
  vpc_id                 = data.terraform_remote_state.infra.outputs.vpc_id
  cluster_name           = try(data.terraform_remote_state.infra.outputs.cluster_name, "${var.project}-${var.env}")
  cluster_endpoint       = data.terraform_remote_state.infra.outputs.cluster_endpoint
  cluster_ca_cert        = data.terraform_remote_state.infra.outputs.cluster_ca_certificate
  lb_controller_role_arn = data.terraform_remote_state.infra.outputs.lb_controller_role_arn
  external_dns_role_arn  = data.terraform_remote_state.infra.outputs.external_dns_role_arn
  main_domain            = data.terraform_remote_state.infra.outputs.domain
  fluentbit_role_arn     = data.terraform_remote_state.infra.outputs.fluentbit_role_arn
  efs_role_arn           = data.terraform_remote_state.infra.outputs.efs_role_arn
  efs_id                 = data.terraform_remote_state.infra.outputs.efs_id
  ebs_csi_irsa_arn       = data.terraform_remote_state.infra.outputs.ebs_csi_irsa_arn
  app_logs               = data.terraform_remote_state.infra.outputs.log_group_names["app_logs"]

  name_prefix          = "kubapp-${var.env}"
  alert_email          = var.alert_email
  alert_email_password = var.alert_email_password

  k8s_labels = {
    cluster_name  = local.cluster_name
    resource-type = "kubernetes"
    env           = var.env
    project       = var.project
    plane         = "k8s"
    runtime       = "helm"
    trace-id      = "${local.cluster_name}-kubernetes"
  }

  monitoring_labels = merge(local.k8s_labels, {
    component = "monitoring"
    workload  = "observability"
    telemetry = "metrics"
  })

  logs_labels = merge(local.k8s_labels, {
    component = "logging"
    workload  = "observability"
    telemetry = "logs"
  })

  namespaces = {
    argocd = {
      component = "gitops"
      workload  = "control-plane"
      labels = {
        Environment = var.env
      }
    }

    monitoring = {
      component = "observability"
      workload  = "monitoring"
      labels = {
        telemetry   = "metrics"
        Environment = var.env
      }
    }

    aws-observability = {
      component = "platform"
      workload  = "logging"

      labels = {
        aws-observability = "enabled"
        Environment       = var.env
      }
    }
    #    user = {
    #      component = "application"
    #      workload  = "users"
    #    }

    #    admin = {
    #      component = "application"
    #      workload  = "admin"
    #    }
  }
}

