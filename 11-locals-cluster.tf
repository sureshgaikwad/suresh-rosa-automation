##############################################################
# Cluster Configuration Locals
##############################################################

locals {
  # Basic configuration
  path                 = coalesce(var.path, "/")
  account_role_prefix  = coalesce(var.account_role_prefix, "${var.cluster_name}-account")
  operator_role_prefix = coalesce(var.operator_role_prefix, "${var.cluster_name}-operator")

  # Determine whether the cluster is private (same logic as the rosa_cluster_hcp module call)
  is_private_cluster = var.private_cluster != null ? var.private_cluster : var.private

  # Compute subnet IDs based on VPC type and cluster visibility
  # - Public cluster (standard VPC):  Pass both public + private subnets (public needed for LBs/ingress)
  # - Private cluster (standard VPC): Pass only private subnets ("Only private subnets permitted" error otherwise)
  # - Zero Egress / Private VPC:      Private subnets only
  # - Existing VPC:                   Use provided subnet IDs as-is (user is responsible)
  cluster_subnet_ids = var.create_vpc ? (
    local.is_private_cluster || var.zero_egress ? module.vpc[0].private_subnets : concat(module.vpc[0].public_subnets, module.vpc[0].private_subnets)
  ) : (var.aws_subnet_ids != null ? var.aws_subnet_ids : [])

  # Computed cluster parameters
  cluster_machine_cidr       = var.zero_egress && var.create_vpc ? module.vpc[0].cidr_block : var.machine_cidr
  cluster_availability_zones = var.create_vpc ? module.vpc[0].availability_zones : var.aws_availability_zones

  # Cluster outputs -- single module, no ternary needed
  cluster_id              = module.rosa_cluster_hcp[0].cluster_id
  cluster_api_url         = module.rosa_cluster_hcp[0].cluster_api_url
  cluster_admin_username  = module.rosa_cluster_hcp[0].cluster_admin_username
  cluster_admin_password  = module.rosa_cluster_hcp[0].cluster_admin_password
  cluster_console_url     = module.rosa_cluster_hcp[0].cluster_console_url
  cluster_domain          = module.rosa_cluster_hcp[0].cluster_domain
  cluster_current_version = module.rosa_cluster_hcp[0].cluster_current_version
  cluster_state           = module.rosa_cluster_hcp[0].cluster_state
}

##############################################################
# IAM Roles and Policies Configuration
##############################################################

locals {
  # STS Role ARNs for ROSA cluster (partition-aware for GovCloud support)
  sts_roles = {
    installer_role_arn = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role${local.path}${local.account_role_prefix}-HCP-ROSA-Installer-Role",
    support_role_arn   = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role${local.path}${local.account_role_prefix}-HCP-ROSA-Support-Role",
    worker_role_arn    = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role${local.path}${local.account_role_prefix}-HCP-ROSA-Worker-Role"
  }

  # OCM (OpenShift Cluster Manager) Policies
  ocm_policies = [
    "arn:aws:iam::aws:policy/service-role/ROSAControlPlaneOperatorPolicy",
    "arn:aws:iam::aws:policy/service-role/ROSAKubeControllerPolicy",
    "arn:aws:iam::aws:policy/service-role/ROSAImageRegistryOperatorPolicy",
    "arn:aws:iam::aws:policy/service-role/ROSAIngressOperatorPolicy",
    "arn:aws:iam::aws:policy/service-role/ROSACloudNetworkConfigOperatorPolicy",
    "arn:aws:iam::aws:policy/service-role/ROSAAmazonEBSCSIDriverOperatorPolicy",
    "arn:aws:iam::aws:policy/service-role/ROSANodePoolManagementPolicy"
  ]
}
