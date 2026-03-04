################################################################################
# ROSA HCP Zero Egress Cluster Example
#
# Deployment options:
# - create_vpc = true  → Creates new zero egress VPC
# - create_vpc = false → Uses existing subnets
################################################################################

locals {
  account_role_prefix  = "${var.cluster_name}-account"
  operator_role_prefix = "${var.cluster_name}-operator"
  subnet_ids           = var.create_vpc ? module.vpc[0].private_subnets : var.existing_subnet_ids
  machine_cidr         = var.create_vpc ? module.vpc[0].cidr_block : var.existing_vpc_cidr
}

################################################################################
# Zero Egress VPC (Optional)
################################################################################

module "vpc" {
  count  = var.create_vpc ? 1 : 0
  source = "../../modules/vpc"

  name_prefix              = var.cluster_name
  vpc_cidr                 = var.vpc_cidr
  availability_zones_count = var.availability_zones_count
  tags                     = var.tags

  # Zero-egress: private subnets only, VPC endpoints, no IGW/NAT
  zero_egress              = true
  create_endpoints         = true
  enable_dynamodb_endpoint = var.enable_dynamodb_endpoint
}

################################################################################
# Validation (when using existing VPC)
################################################################################

resource "null_resource" "validation" {
  count = var.create_vpc ? 0 : 1

  lifecycle {
    precondition {
      condition     = var.existing_subnet_ids != null && length(var.existing_subnet_ids) > 0
      error_message = "existing_subnet_ids required when create_vpc is false."
    }
    precondition {
      condition     = var.existing_vpc_cidr != null
      error_message = "existing_vpc_cidr required when create_vpc is false."
    }
  }
}

################################################################################
# IAM Resources
################################################################################

module "account_iam" {
  source = "../../modules/account-iam-resources"

  account_role_prefix = local.account_role_prefix
  path                = var.path
  tags                = var.tags
}

module "oidc" {
  source = "../../modules/oidc-config-and-provider"

  managed            = true
  installer_role_arn = module.account_iam.account_roles_arn["HCP-ROSA-Installer"]
  tags               = var.tags
}

module "operator_roles" {
  source = "../../modules/operator-roles"

  operator_role_prefix = local.operator_role_prefix
  path                 = var.path
  oidc_endpoint_url    = module.oidc.oidc_endpoint_url
  tags                 = var.tags
}

################################################################################
# Zero Egress ROSA Cluster
################################################################################

module "cluster" {
  source = "../../modules/rosa-cluster-hcp"

  cluster_name            = var.cluster_name
  openshift_version       = var.openshift_version
  aws_subnet_ids          = local.subnet_ids
  subnet_ids_are_computed = var.create_vpc
  machine_cidr            = local.machine_cidr

  # Zero-egress overrides: private, internal ingress, IMDSv2 required
  private                          = true
  default_ingress_listening_method = "internal"
  ec2_metadata_http_tokens         = "required"
  properties                       = merge(coalesce(var.tags, {}), { zero_egress = "true" })

  # IAM
  oidc_config_id       = module.oidc.oidc_config_id
  account_role_prefix  = local.account_role_prefix
  operator_role_prefix = local.operator_role_prefix
  installer_role_arn   = module.account_iam.account_roles_arn["HCP-ROSA-Installer"]
  support_role_arn     = module.account_iam.account_roles_arn["HCP-ROSA-Support"]
  worker_role_arn      = module.account_iam.account_roles_arn["HCP-ROSA-Worker"]

  # Compute
  replicas             = var.replicas
  compute_machine_type = var.compute_machine_type

  # Admin
  create_admin_user          = var.create_admin_user
  admin_credentials_username = var.create_admin_user ? "cluster-admin" : null
  admin_credentials_password = var.create_admin_user ? random_password.admin[0].result : null

  tags = var.tags

  depends_on = [module.vpc, module.account_iam, module.oidc, module.operator_roles]
}

################################################################################
# Admin Password
################################################################################

resource "random_password" "admin" {
  count            = var.create_admin_user ? 1 : 0
  length           = 16
  special          = true
  min_lower        = 1
  min_numeric      = 1
  min_special      = 1
  min_upper        = 1
  override_special = "!@#$%^&*"
}

################################################################################
# OPTIONAL: Image Mirrors (uncomment if needed for disconnected environments)
################################################################################

# module "mirror_redhat" {
#   source          = "../../modules/image-mirrors"
#   cluster_id      = module.cluster.cluster_id
#   type            = "digest"
#   source_registry = "registry.redhat.io"
#   mirrors         = ["your-registry.dkr.ecr.region.amazonaws.com/redhat"]
# }
