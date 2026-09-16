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
  vpc_cidr     = "10.0.0.0/16"
  azs          = ["us-east-1a", "us-east-1b"]

  public_subnets   = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets  = ["10.0.11.0/24", "10.0.12.0/24"]
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
  source = "./modules/sg-prep"

  from_port_ec2_app = 3000
  to_port_ec2_app   = 3000

  from_port_fargate_app = 4000
  to_port_fargate_app   = 4000

  from_port_cache_app = 6379
  to_port_cache_app   = 6379

  private_subnets_cidr = ["10.0.11.0/24", "10.0.12.0/24"]

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
  source          = "./modules/iam-core"
  cluster_name    = local.cluster_name
  account_id      = var.account_id
  tf_state_bucket = local.tf_state_bucket
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
  account_id        = data.aws_caller_identity.current.account_id

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
  sg_ids             = module.security.sg_ids

  cluster_role_arn  = module.iam_core.eks_cluster_role_arn
  node_role_arn     = module.iam_core.node_group_role_arn
  fargate_role_arn  = module.iam_core.fargate_role_arn
  fargate_workloads = local.fargate_workloads
  #sys_monitor_ec2_role_arn                   = module.iam_core.sys_monitor_ec2_role_arn
  sys_monitor_eks_cross_account_role_arn = module.iam_core.sys_monitor_eks_cross_account_role

  access_iam_arn = var.access_iam_arn
  admin_arn      = var.admin_arn

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
  vpc_cidr     = "10.0.0.0/16"
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

