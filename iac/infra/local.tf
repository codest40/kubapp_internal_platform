locals {
  account_id = data.aws_caller_identity.current.account_id
}

data "terraform_remote_state" "dns" {
  backend = "s3"
  config = {
    bucket = "kubapp-dns-tf-state-${local.account_id}"
    key    = "dns/terraform.tfstate"
    region = "us-east-1"
  }
}

locals {
  name_prefix     = "${var.project}-${var.env}"
  cluster_name    = "${var.cluster_name}-${var.env}"
  tf_state_bucket = "kubapp-tf-state-${local.account_id}"
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
    owner      = "kubapp-platform"
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

    fargate_logs = {
      name      = "/aws/eks/${local.cluster_name}/fargate"
      retention = var.log_groups.app_logs.retention
      log_type  = "fargate"
      scope     = "workload"
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

  all_workloads = {
    labels_fargate = {
      compute = "fargate"
    }

    labels_ec2 = {
      compute = "ec2"
    }
  }

  workloads = {
    for name, workload in local.all_workloads :
    name => merge(workload, {
      env = var.env
    })
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

  full_domain                 = "${var.env}.${var.main_domain}"
  sys_monitor_active          = var.sys_monitor_enabled
  sys_monitor_rbac_group_name = "sys-monitor-gitops"
  sys_monitor_ec2_role_arn    = "arn:aws:iam::${local.account_id}:role/sys-monitor-ec2-role"
  cross_account_role          = "arn:aws:iam::${var.cross_account_ids["monitor"]}:role/sys-monitor-ec2-role"
  cross_account_role_arn = (
    var.cross_account_ids["monitor"] == "" ||
    var.cross_account_ids["monitor"] == null
    ? null
    : local.cross_account_role
  )
  enable_cross_account = (
    local.sys_monitor_active &&
    var.cross_account_ids["monitor"] != "" &&
    var.cross_account_ids["monitor"] != null
  )

  admin_kubapp_arn         = "arn:aws:iam::${local.account_id}:user/${var.admin_kubapp}"
  admin_sys_monitor_arn    = "arn:aws:iam::${var.cross_account_ids["monitor"]}:user/${var.admin_sys_monitor}"
  admin_github_arn         = "arn:aws:iam::${local.account_id}:role/${var.admin_github}"
  visitor_account_user_arn = "arn:aws:iam::${local.account_id}:role/${var.admin_visitor}"
  kubapp_account_user      = split("/", local.admin_kubapp_arn)[1]
  sys_monitor_account_user = split("/", local.admin_sys_monitor_arn)[1]

  # Network
  vpc_cidr             = "10.0.0.0/16"
  azs                  = ["us-east-1a", "us-east-1b"]
  public_subnets       = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets      = ["10.0.11.0/24", "10.0.12.0/24"]
  private_subnets_cidr = ["10.0.11.0/24", "10.0.12.0/24"]

  # Database
  database_account_arn = "arn:aws:iam::${var.cross_account_ids["db"]}:role/${var.database_role}"
  db_lets_kubapp_read_state_arn = (
    "arn:aws:iam::${var.cross_account_ids["db"]}:role/${var.db_kubapp_reciever_role}"
  )

  db_mode_enabled = (
    var.db_enabled &&
    var.cross_account_ids["db"] != "" &&
    var.cross_account_ids["db"] != null
  )

  enable_db_cross_account = (
    local.db_mode_enabled &&
    local.account_id != var.cross_account_ids["db"] &&
    var.enable_db_local_account == false
  )

  show_database_state = (
    local.enable_db_cross_account ? "cross" :
    var.enable_db_local_account ? "local" :
    "disabled"
  )

  database_state_bucket      = "kubapp-database-tf-state-${var.cross_account_ids["db"]}"
  database_state_key         = "${var.env}/database/tf-state"
  allow_kubapp_read_db_state = false
}

