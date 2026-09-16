data "terraform_remote_state" "dns" {
  backend = "s3"
  config = {
    bucket = "kubapp-dns-tf-state-${var.account_id}"
    key    = "dns/terraform.tfstate"
    region = "us-east-1"
  }
}

locals {
  name_prefix     = "${var.project}-${var.env}"
  cluster_name    = "${var.cluster_name}-${var.env}"
  tf_state_bucket = "kubapp-tf-state-${var.account_id}"
  main_domain     = data.terraform_remote_state.dns.outputs.domains[var.main_domain]["domain"]
  dns_zone_id     = data.terraform_remote_state.dns.outputs.domains[var.main_domain]["zone_id"]

  # GLOBAL TRACE ID 
  trace_id = "${var.project}-${var.env}-${local.cluster_name}"

  base_tags = {
    project = var.project
    env     = var.env
    cluster = local.cluster_name

    trace-id   = local.trace_id
    plane      = "infra"
    owner      = "platform"
    managed-by = "terraform"
  }

  common_tags = local.base_tags

  # ----------------------------
  # App log groups
  # ----------------------------
  app_log_groups = {
    app_logs = {
      name      = "/${var.project}/${var.env}/app-logs"
      retention = var.log_groups.app_logs.retention
      log_type  = "application"
      scope     = "workload"
    }

    audit_logs = {
      name      = "/${var.project}/${var.env}/audit-logs"
      retention = var.log_groups.audit_logs.retention
      log_type  = "security"
      scope     = "system"
    }

    # ----------------------------
    # EKS system log group
    # ----------------------------
    eks_cluster_log_group = {
      name      = "/aws/eks/${local.cluster_name}/cluster"
      retention = var.log_groups.cluster_logs.retention
      log_type  = "eks"
      scope     = "cluster"
    }

    vpc_flow_log = {
      name      = "/aws/vpc/${local.cluster_name}-flowlogs"
      retention = var.log_groups.vpc_logs.retention
      log_type  = "network"
      scope     = "network"
    }
  }

  fargate_workloads = {
    dev = {
      role = "applications"
      labels = {
        compute = "fargate"
      }
    }

    prod = {
      role = "applications"
      labels = {
        compute = "fargate"
      }
    }
  }

  base_node_config = {
    node_instance_type    = "t3.large"
    node_desired_capacity = 2
    node_min_capacity     = 1
    node_max_capacity     = 3
  }

  app_nodes = local.base_node_config

  sys_nodes = merge(local.base_node_config, {
    node_desired_capacity = 2
    node_max_capacity     = 2
  })

  # Just for tag
  full_domain = "${var.env}.${var.main_domain}"

}

