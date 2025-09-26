##############################################################
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