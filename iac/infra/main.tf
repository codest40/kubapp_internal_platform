############################################
# AUTH DATA
############################################

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

data "aws_caller_identity" "current" {}


############################################
# NETWORK
############################################

module "network" {
  source = "./modules/network"

  name         = local.name_prefix
  cluster_name = local.cluster_name
  vpc_cidr     = local.vpc_cidr
  azs          = local.azs

  public_subnets   = local.public_subnets
  private_subnets  = local.private_subnets
  vpc_flow_log_arn = module.logging.log_group_arns["vpc_flow_log"]
  tags = merge(local.common_tags, {
    layer = "network"
    name  = local.name_prefix
  })
}

############################################
# SG PREP
############################################

module "sg_prep" {
  source   = "./modules/sg-prep"
  vpc_cidr = local.vpc_cidr

  from_port_ec2_app = 3000
  to_port_ec2_app   = 3000

  from_port_fargate_app = 4000
  to_port_fargate_app   = 4000

  from_port_db_access = 6379
  to_port_db_access   = 6379

  private_subnets_cidr  = local.private_subnets_cidr
  custom_sg_definitions = {}

  tags = local.common_tags
}

############################################
# SECURITY
############################################
module "security" {
  source = "./modules/security"

  vpc_id         = module.network.vpc_id
  sg_definitions = module.sg_prep.sg_definitions

  name_prefix  = local.name_prefix
  cluster_name = local.cluster_name
  tags = merge(local.common_tags, {
    resource-type = "security-group"
    layer         = "security"
  })
}

############################################
# IAM 
############################################
module "iam_core" {
  source                       = "./modules/iam-core"
  cluster_name                 = local.cluster_name
  account_id                   = local.account_id
  tf_state_bucket              = local.tf_state_bucket
  fargate_log_group_arn        = module.logging.log_group_arns["fargate_logs"]
  enable_cross_account         = local.enable_cross_account
  cross_account_role_arn       = local.cross_account_role_arn
  kubapp_account_user          = local.kubapp_account_user
  kubapp_account_user_arn      = local.admin_kubapp_arn
  visitor_account_user_arn     = local.visitor_account_user_arn
  sys_monitor_account_user     = local.sys_monitor_account_user
  sys_monitor_account_user_arn = local.admin_sys_monitor_arn
  admin_github_arn             = local.admin_github_arn
  enable_db_cross_account      = local.enable_db_cross_account
  database_account_arn         = local.database_account_arn
  zone_id                      = local.dns_zone_id

  tags = merge(local.common_tags, {
    resource-type = "iam"
    layer         = "identity"
    step          = "base"
  })
}

# Roles
module "iam_irsa" {
  source = "./modules/iam-irsa"

  cluster_name      = local.cluster_name
  region            = var.region
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  hosted_zone_id    = local.dns_zone_id
  account_id        = local.account_id

  tags = merge(local.common_tags, {
    resource-type = "iam"
    layer         = "identity"
    step          = "extra"
  })
  depends_on = [module.eks]
}

############################################
# EKS
############################################
module "eks" {
  source = "./modules/eks"

  cluster_name       = local.cluster_name
  kubernetes_version = var.kubernetes_v
  vpc_id             = module.network.vpc_id
  private_subnet_ids = module.network.private_subnet_ids

  cluster_role_arn                       = module.iam_core.eks_cluster_role_arn
  node_role_arn                          = module.iam_core.node_group_role_arn
  fargate_role_arn                       = module.iam_core.fargate_role_arn
  fargate_workloads                      = local.workloads.labels_fargate
  sys_monitor_eks_cross_account_role_arn = module.iam_core.sys_monitor_eks_cross_account_role
  enable_cross_account                   = local.enable_cross_account
  sys_monitor_ec2_role_arn               = local.sys_monitor_ec2_role_arn
  sys_monitor_rbac_group_name            = local.sys_monitor_rbac_group_name

  github_iam_arn = local.admin_github_arn
  admin_iam_arn  = local.admin_kubapp_arn

  node_instance_type    = local.app_nodes.node_instance_type
  node_desired_capacity = local.app_nodes.node_desired_capacity
  node_min_capacity     = local.app_nodes.node_min_capacity
  node_max_capacity     = local.app_nodes.node_max_capacity

  sys_node_instance_type    = local.sys_nodes.node_instance_type
  sys_node_desired_capacity = local.sys_nodes.node_desired_capacity
  sys_node_min_capacity     = local.sys_nodes.node_min_capacity
  sys_node_max_capacity     = local.sys_nodes.node_max_capacity

  tags = merge(local.common_tags, {
    layer        = "compute"
    cluster-role = "control-plane"
  })

  depends_on = [
    module.logging,
    module.network
  ]
}

############################################
# CLOUDWATCH
############################################

module "logging" {
  source       = "./modules/logging"
  log_groups   = local.app_log_groups
  name_prefix  = local.name_prefix
  cluster_name = local.cluster_name

  tags = merge(local.common_tags, {
    resource-type = "cloudwatch"
    layer         = "observability"
  })
}

############################################
# EFS       
############################################
module "efs" {
  source = "./modules/efs"

  vpc_id       = module.network.vpc_id
  vpc_cidr     = local.vpc_cidr
  name_prefix  = local.name_prefix
  cluster_name = local.cluster_name
  subnet_ids   = module.network.private_subnet_ids
  tags = merge(local.common_tags, {
    resource-type = "efs"
    layer         = "storage"
  })
  #efs_access_points = local.efs_access_points
}

############################################
# ACM
############################################
module "acm" {
  source  = "./modules/acm"
  domain  = local.main_domain
  zone_id = local.dns_zone_id
  tags = merge(local.common_tags, {
    resource-type = "acm"
    layer         = "routing"
  })
}


############################################
# DATABASE
############################################
module "database" {
  count  = local.db_mode_enabled ? 1 : 0
  source = "./modules/database"

  enable_db_cross_account    = local.enable_db_cross_account
  allow_kubapp_read_db_state = local.allow_kubapp_read_db_state

  kubapp_vpc_id                  = module.network.vpc_id
  kubapp_private_route_table_ids = module.network.private_route_table_ids
  kubapp_vpc_cidr                = local.vpc_cidr

  database_account_id           = var.cross_account_ids["db"]
  database_state_bucket         = local.database_state_bucket
  database_state_key            = local.database_state_key
  db_lets_kubapp_read_state_arn = local.db_lets_kubapp_read_state_arn

  admin_kubapp_arn = local.admin_kubapp_arn
  admin_github_arn = local.admin_github_arn
  env              = var.env
  region           = var.region

  tags = merge(local.common_tags, {
    resource-type = "database"
    layer         = "storage"
  })
}
