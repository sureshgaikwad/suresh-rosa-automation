##############################################################
# Account roles includes IAM roles and IAM policies
##############################################################

module "account_iam_resources" {
  source = "./modules/account-iam-resources"
  count  = var.create_account_roles ? 1 : 0

  account_role_prefix  = local.account_role_prefix
  path                 = local.path
  permissions_boundary = var.permissions_boundary
  tags                 = var.tags
}

############################
# OIDC config and provider
############################
module "oidc_config_and_provider" {
  source = "./modules/oidc-config-and-provider"
  count  = var.create_oidc ? 1 : 0

  managed = var.managed_oidc
  installer_role_arn = var.managed_oidc ? (null) : (
    var.create_account_roles ? (module.account_iam_resources[0].account_roles_arn["HCP-ROSA-Installer"]) : (
      local.sts_roles.installer_role_arn
    )
  )
  tags = var.tags
}

############################
# operator roles
############################
module "operator_roles" {
  source = "./modules/operator-roles"
  count  = var.create_operator_roles ? 1 : 0

  operator_role_prefix = local.operator_role_prefix
  path                 = local.path
  oidc_endpoint_url    = var.create_oidc ? module.oidc_config_and_provider[0].oidc_endpoint_url : var.oidc_endpoint_url
  tags                 = var.tags
  permissions_boundary = var.permissions_boundary
}

############################
# ROSA STS cluster
############################
resource "rhcs_dns_domain" "dns_domain" {
  count        = var.create_dns_domain_reservation ? 1 : 0
  cluster_arch = "hcp"
}

module "rosa_cluster_hcp" {
  source = "./modules/rosa-cluster-hcp"

  cluster_name            = var.cluster_name
  operator_role_prefix    = var.create_operator_roles ? module.operator_roles[0].operator_role_prefix : local.operator_role_prefix
  openshift_version       = var.openshift_version
  version_channel_group   = var.version_channel_group
  installer_role_arn      = var.create_account_roles ? module.account_iam_resources[0].account_roles_arn["HCP-ROSA-Installer"] : local.sts_roles.installer_role_arn
  support_role_arn        = var.create_account_roles ? module.account_iam_resources[0].account_roles_arn["HCP-ROSA-Support"] : local.sts_roles.support_role_arn
  worker_role_arn         = var.create_account_roles ? module.account_iam_resources[0].account_roles_arn["HCP-ROSA-Worker"] : local.sts_roles.worker_role_arn
  oidc_config_id          = var.create_oidc ? module.oidc_config_and_provider[0].oidc_config_id : var.oidc_config_id
  aws_subnet_ids          = local.cluster_subnet_ids
  subnet_ids_are_computed = var.create_vpc

  depends_on                        = [module.vpc]
  machine_cidr                      = var.machine_cidr
  service_cidr                      = var.service_cidr
  pod_cidr                          = var.pod_cidr
  host_prefix                       = var.host_prefix
  private                           = var.private_cluster != null ? var.private_cluster : var.private
  tags                              = var.tags
  properties                        = var.properties
  etcd_encryption                   = var.enable_etcd_encryption ? var.etcd_encryption : null
  etcd_kms_key_arn                  = var.enable_etcd_encryption ? var.etcd_kms_key_arn : null
  kms_key_arn                       = var.enable_ebs_encryption ? var.kms_key_arn : null
  aws_billing_account_id            = var.aws_billing_account_id
  ec2_metadata_http_tokens          = var.ec2_metadata_http_tokens
  base_dns_domain                   = var.create_dns_domain_reservation ? rhcs_dns_domain.dns_domain[0].id : var.base_dns_domain
  aws_additional_allowed_principals = var.aws_additional_allowed_principals

  ########
  # Cluster Admin User
  ########  
  create_admin_user          = var.create_admin_user
  admin_credentials_username = coalesce(var.admin_credentials_username, var.admin_username)
  admin_credentials_password = var.admin_credentials_password

  ########
  # Flags
  ########
  wait_for_create_complete            = var.wait_for_create_complete
  wait_for_std_compute_nodes_complete = var.wait_for_std_compute_nodes_complete
  disable_waiting_in_destroy          = var.disable_waiting_in_destroy
  destroy_timeout                     = var.destroy_timeout
  upgrade_acknowledgements_for        = var.upgrade_acknowledgements_for

  #######################
  # Default Machine Pool
  #######################

  replicas                                  = var.replicas
  compute_machine_type                      = var.compute_machine_type
  aws_availability_zones                    = var.create_vpc ? module.vpc[0].availability_zones : var.aws_availability_zones
  aws_additional_compute_security_group_ids = var.aws_additional_compute_security_group_ids

  ########
  # Proxy 
  ########
  http_proxy              = var.enable_proxy ? var.http_proxy : null
  https_proxy             = var.enable_proxy ? var.https_proxy : null
  no_proxy                = var.enable_proxy ? var.no_proxy : null
  additional_trust_bundle = var.enable_proxy ? var.additional_trust_bundle : null

  #############
  # Autoscaler 
  #############
  cluster_autoscaler_enabled         = false
  autoscaler_max_pod_grace_period    = var.autoscaler_max_pod_grace_period
  autoscaler_pod_priority_threshold  = var.autoscaler_pod_priority_threshold
  autoscaler_max_node_provision_time = var.autoscaler_max_node_provision_time
  autoscaler_max_nodes_total         = var.autoscaler_max_nodes_total

  ##################
  # default_ingress 
  ##################
  default_ingress_listening_method = var.default_ingress_listening_method != "" ? (
    var.default_ingress_listening_method) : (
    var.private ? "internal" : "external"
  )
}

######################################
# Multiple Machine Pools Generic block
######################################



###########################################
# Multiple Identity Providers Generic block
###########################################

module "rhcs_identity_provider" {
  source   = "./modules/idp"
  for_each = var.create_identity_providers ? var.identity_providers : {}

  cluster_id                            = module.rosa_cluster_hcp.cluster_id
  name                                  = each.value.name
  idp_type                              = each.value.idp_type
  mapping_method                        = try(each.value.mapping_method, null)
  github_idp_client_id                  = try(each.value.github_idp_client_id, null)
  github_idp_client_secret              = try(each.value.github_idp_client_secret, null)
  github_idp_ca                         = try(each.value.github_idp_ca, null)
  github_idp_hostname                   = try(each.value.github_idp_hostname, null)
  github_idp_organizations              = try(jsondecode(each.value.github_idp_organizations), null)
  github_idp_teams                      = try(jsondecode(each.value.github_idp_teams), null)
  gitlab_idp_client_id                  = try(each.value.gitlab_idp_client_id, null)
  gitlab_idp_client_secret              = try(each.value.gitlab_idp_client_secret, null)
  gitlab_idp_url                        = try(each.value.gitlab_idp_url, null)
  gitlab_idp_ca                         = try(each.value.gitlab_idp_ca, null)
  google_idp_client_id                  = try(each.value.google_idp_client_id, null)
  google_idp_client_secret              = try(each.value.google_idp_client_secret, null)
  google_idp_hosted_domain              = try(each.value.google_idp_hosted_domain, null)
  htpasswd_idp_users                    = try(jsondecode(each.value.htpasswd_idp_users), null)
  ldap_idp_bind_dn                      = try(each.value.ldap_idp_bind_dn, null)
  ldap_idp_bind_password                = try(each.value.ldap_idp_bind_password, null)
  ldap_idp_ca                           = try(each.value.ldap_idp_ca, null)
  ldap_idp_insecure                     = try(each.value.ldap_idp_insecure, null)
  ldap_idp_url                          = try(each.value.ldap_idp_url, null)
  ldap_idp_emails                       = try(jsondecode(each.value.ldap_idp_emails), null)
  ldap_idp_ids                          = try(jsondecode(each.value.ldap_idp_ids), null)
  ldap_idp_names                        = try(jsondecode(each.value.ldap_idp_names), null)
  ldap_idp_preferred_usernames          = try(jsondecode(each.value.ldap_idp_preferred_usernames), null)
  openid_idp_ca                         = try(each.value.openid_idp_ca, null)
  openid_idp_claims_email               = try(jsondecode(each.value.openid_idp_claims_email), null)
  openid_idp_claims_groups              = try(jsondecode(each.value.openid_idp_claims_groups), null)
  openid_idp_claims_name                = try(jsondecode(each.value.openid_idp_claims_name), null)
  openid_idp_claims_preferred_username  = try(jsondecode(each.value.openid_idp_claims_preferred_username), null)
  openid_idp_client_id                  = try(each.value.openid_idp_client_id, null)
  openid_idp_client_secret              = try(each.value.openid_idp_client_secret, null)
  openid_idp_extra_scopes               = try(jsondecode(each.value.openid_idp_extra_scopes), null)
  openid_idp_extra_authorize_parameters = try(jsondecode(each.value.openid_idp_extra_authorize_parameters), null)
  openid_idp_issuer                     = try(each.value.openid_idp_issuer, null)
}

######################################
# Multiple Kubelet Configs block
######################################
module "rhcs_hcp_kubelet_configs" {
  source   = "./modules/kubelet-configs"
  for_each = var.kubelet_configs

  cluster_id     = module.rosa_cluster_hcp.cluster_id
  name           = each.value.name
  pod_pids_limit = each.value.pod_pids_limit
}

resource "null_resource" "validations" {
  lifecycle {
    precondition {
      condition     = (var.create_operator_roles == true && var.create_oidc != true && var.oidc_endpoint_url == null) == false
      error_message = "\"oidc_endpoint_url\" mustn't be empty when oidc is pre-created (create_oidc != true)."
    }
    precondition {
      condition     = (var.create_oidc != true && var.oidc_config_id == null) == false
      error_message = "\"oidc_config_id\" mustn't be empty when oidc is pre-created (create_oidc != true)."
    }
  }
}

##############################################################
# VPC Module (Optional)
##############################################################

module "vpc" {
  count  = var.create_vpc ? 1 : 0
  source = "./modules/vpc"

  name_prefix              = var.cluster_name
  vpc_cidr                 = var.vpc_cidr
  availability_zones       = var.availability_zones
  availability_zones_count = var.availability_zones_count
  tags                     = var.tags
}

# Validation for VPC configuration
resource "null_resource" "vpc_validation" {
  count = var.create_vpc ? 0 : 1

  lifecycle {
    precondition {
      condition     = var.aws_subnet_ids != null && length(var.aws_subnet_ids) > 0
      error_message = "aws_subnet_ids must be provided when create_vpc is false."
    }
  }
}

##############################################################
# Machine Pools
##############################################################

module "rhcs_hcp_machine_pool" {
  source   = "./modules/machine-pool"
  for_each = var.create_additional_machine_pools ? var.machine_pools : {}

  cluster_id = module.rosa_cluster_hcp.cluster_id
  name       = each.value.name

  # Machine pool configuration - replicas OR autoscaling, not both
  replicas    = try(each.value.autoscaling, null) != null ? null : try(each.value.replicas, 2)
  auto_repair = try(each.value.auto_repair, true)

  # Autoscaling configuration - properly structured
  autoscaling = try(each.value.autoscaling, null) != null ? {
    enabled      = true
    min_replicas = try(each.value.autoscaling.min_replicas, 1)
    max_replicas = try(each.value.autoscaling.max_replicas, 5)
    } : {
    enabled      = false
    min_replicas = null
    max_replicas = null
  }

  # AWS node pool configuration
  aws_node_pool = {
    instance_type                 = try(each.value.instance_type, "m5.xlarge")
    tags                          = merge(var.tags, try(each.value.tags, {}))
    additional_security_group_ids = try(each.value.additional_security_group_ids, null)
  }

  # Subnet configuration - machine pools should use private subnets
  subnet_id = try(each.value.subnet_id, var.create_vpc ? module.vpc[0].private_subnets[0] : (var.aws_subnet_ids != null && length(var.aws_subnet_ids) > 0 ? var.aws_subnet_ids[0] : null))

  # Required OpenShift version
  openshift_version = var.openshift_version

  # Optional configurations
  tuning_configs               = try(each.value.tuning_configs, null)
  upgrade_acknowledgements_for = try(each.value.upgrade_acknowledgements_for, null)
  taints                       = try(each.value.taints, null)
  labels                       = try(each.value.labels, null)
  kubelet_configs              = try(each.value.kubelet_configs, null)

  depends_on = [module.rosa_cluster_hcp]
}

##############################################################
# Bastion Host
##############################################################

# Note: Bastion host requires existing VPC and subnets. 
# For new VPC creation, bastion host will be created in the VPC module separately.
# This is only for existing VPC scenarios.
# To enable bastion host with existing VPC, provide aws_subnet_ids in variables.

##############################################################
# OCM Role (Optional)
##############################################################

resource "aws_iam_role" "ocm_role" {
  count = var.create_ocm_role ? 1 : 0
  name  = var.ocm_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::710019948333:root" # Red Hat's OCM service account
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "sts:ExternalId" = "RedHatManaged"
          }
        }
      }
    ]
  })

  tags = merge(var.tags, {
    "red-hat-managed" = "true"
    "rosa_role_type"  = "ocm"
  })
}

# Policy attachments for OCM role
resource "aws_iam_role_policy_attachment" "ocm_role_policies" {
  count = var.create_ocm_role ? length(local.ocm_policies) : 0

  role       = aws_iam_role.ocm_role[0].name
  policy_arn = local.ocm_policies[count.index]
}
