##############################################################
# Local Values and Computed Dependencies
##############################################################

locals {
  # Basic configuration
  path                 = coalesce(var.path, "/")
  account_role_prefix  = coalesce(var.account_role_prefix, "${var.cluster_name}-account")
  operator_role_prefix = coalesce(var.operator_role_prefix, "${var.cluster_name}-operator")

  # Compute subnet IDs - when creating VPC, use both public and private subnets, otherwise use provided subnet IDs
  cluster_subnet_ids = var.create_vpc ? concat(module.vpc[0].public_subnets, module.vpc[0].private_subnets) : (var.aws_subnet_ids != null ? var.aws_subnet_ids : [])
}