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
}##############################################################
# OpenShift Features and Dependencies Logic
##############################################################

locals {
  # Dependency logic: When OpenShift AI is enabled, automatically enable prerequisite operators
  # This ensures that all required dependencies are deployed when OpenShift AI is requested
  deploy_nfd                             = var.deploy_openshift_ai ? true : var.deploy_nfd
  deploy_nvidia_gpu_operator             = var.deploy_openshift_ai ? true : var.deploy_nvidia_gpu_operator
  deploy_openshift_servicemesh           = var.deploy_openshift_ai ? true : var.deploy_openshift_servicemesh
  deploy_openshift_serverless            = var.deploy_openshift_ai ? true : var.deploy_openshift_serverless
  deploy_openshift_lightspeed            = var.deploy_openshift_ai ? true : var.deploy_openshift_lightspeed
}##############################################################
# IAM Roles and Policies Configuration
##############################################################

locals {
  # STS Role ARNs for ROSA cluster
  sts_roles = {
    installer_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role${local.path}${local.account_role_prefix}-HCP-ROSA-Installer-Role",
    support_role_arn   = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role${local.path}${local.account_role_prefix}-HCP-ROSA-Support-Role",
    worker_role_arn    = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role${local.path}${local.account_role_prefix}-HCP-ROSA-Worker-Role"
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