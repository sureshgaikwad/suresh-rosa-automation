##############################################################
# ROSA HCP Cluster Deployment - Main Configuration
#
# This file contains only module calls following Terraform best practices.
# All resource logic is encapsulated in reusable modules.
##############################################################

##############################################################
# Account IAM Resources
##############################################################

module "account_iam_resources" {
  source = "./modules/account-iam-resources"
  count  = var.create_account_roles ? 1 : 0

  account_role_prefix  = local.account_role_prefix
  path                 = local.path
  permissions_boundary = var.permissions_boundary
  tags                 = var.tags
}

##############################################################
# OIDC Configuration and Provider
##############################################################

module "oidc_config_and_provider" {
  source = "./modules/oidc-config-and-provider"
  count  = var.create_oidc ? 1 : 0

  managed = var.managed_oidc
  installer_role_arn = var.managed_oidc ? null : (
    var.create_account_roles ? module.account_iam_resources[0].account_roles_arn["HCP-ROSA-Installer"] : local.sts_roles.installer_role_arn
  )
  tags = var.tags
}

##############################################################
# Operator Roles
##############################################################

module "operator_roles" {
  source = "./modules/operator-roles"
  count  = var.create_operator_roles ? 1 : 0

  operator_role_prefix = local.operator_role_prefix
  path                 = local.path
  oidc_endpoint_url    = var.create_oidc ? module.oidc_config_and_provider[0].oidc_endpoint_url : var.oidc_endpoint_url
  tags                 = var.tags
  permissions_boundary = var.permissions_boundary
}

##############################################################
# DNS Domain Reservation
##############################################################

resource "rhcs_dns_domain" "dns_domain" {
  count        = var.create_dns_domain_reservation ? 1 : 0
  cluster_arch = "hcp"
}

##############################################################
# VPC Module (handles both standard and zero-egress)
##############################################################

module "vpc" {
  source = "./modules/vpc"
  count  = var.create_vpc ? 1 : 0

  name_prefix              = var.cluster_name
  vpc_cidr                 = var.vpc_cidr
  availability_zones       = var.availability_zones
  availability_zones_count = var.availability_zones_count
  tags                     = var.tags

  # Zero-egress options (private subnets only, VPC endpoints, no IGW/NAT)
  zero_egress          = var.zero_egress
  create_endpoints     = var.zero_egress ? var.zero_egress_vpc_endpoints : false
  additional_endpoints = var.zero_egress ? var.zero_egress_additional_endpoints : []
}

##############################################################
# ROSA HCP Cluster (handles both standard and zero-egress)
##############################################################

module "rosa_cluster_hcp" {
  source = "./modules/rosa-cluster-hcp"
  count  = 1

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

  depends_on = [module.vpc]

  # Network configuration
  machine_cidr = local.cluster_machine_cidr
  service_cidr = var.service_cidr
  pod_cidr     = var.pod_cidr
  host_prefix  = var.host_prefix

  # Zero-egress enforces: private=true, internal ingress, IMDSv2 required, zero_egress property
  private                          = local.is_private_cluster || var.zero_egress
  default_ingress_listening_method = var.zero_egress ? "internal" : (var.default_ingress_listening_method != "" ? var.default_ingress_listening_method : (local.is_private_cluster ? "internal" : "external"))
  ec2_metadata_http_tokens         = var.zero_egress ? "required" : var.ec2_metadata_http_tokens
  properties                       = var.zero_egress ? merge(coalesce(var.properties, {}), { zero_egress = "true" }) : var.properties

  tags                              = var.tags
  etcd_encryption                   = var.enable_etcd_encryption ? var.etcd_encryption : null
  etcd_kms_key_arn                  = var.enable_etcd_encryption ? var.etcd_kms_key_arn : null
  kms_key_arn                       = var.enable_ebs_encryption ? var.kms_key_arn : null
  aws_billing_account_id            = var.aws_billing_account_id
  base_dns_domain                   = var.create_dns_domain_reservation ? rhcs_dns_domain.dns_domain[0].id : var.base_dns_domain
  domain_prefix                     = var.domain_prefix
  shared_vpc                        = var.shared_vpc
  aws_additional_allowed_principals = var.aws_additional_allowed_principals

  # Cluster Admin User
  create_admin_user          = var.create_admin_user
  admin_credentials_username = coalesce(var.admin_credentials_username, var.admin_username)
  admin_credentials_password = var.admin_credentials_password

  # Lifecycle Flags
  wait_for_create_complete            = var.wait_for_create_complete
  wait_for_std_compute_nodes_complete = var.wait_for_std_compute_nodes_complete
  disable_waiting_in_destroy          = var.disable_waiting_in_destroy
  destroy_timeout                     = var.destroy_timeout
  upgrade_acknowledgements_for        = var.upgrade_acknowledgements_for

  # Default Machine Pool
  replicas                                  = var.replicas
  compute_machine_type                      = var.compute_machine_type
  worker_disk_size                          = var.worker_disk_size
  aws_availability_zones                    = local.cluster_availability_zones
  aws_additional_compute_security_group_ids = var.aws_additional_compute_security_group_ids

  # Proxy Configuration
  http_proxy              = var.enable_proxy ? var.http_proxy : null
  https_proxy             = var.enable_proxy ? var.https_proxy : null
  no_proxy                = var.enable_proxy ? var.no_proxy : null
  additional_trust_bundle = var.enable_proxy ? var.additional_trust_bundle : null

  # Registry Configuration
  registry_config = var.registry_config

  # Autoscaler
  cluster_autoscaler_enabled         = false
  autoscaler_max_pod_grace_period    = var.autoscaler_max_pod_grace_period
  autoscaler_pod_priority_threshold  = var.autoscaler_pod_priority_threshold
  autoscaler_max_node_provision_time = var.autoscaler_max_node_provision_time
  autoscaler_max_nodes_total         = var.autoscaler_max_nodes_total
}

##############################################################
# Identity Providers
##############################################################

module "rhcs_identity_provider" {
  source   = "./modules/idp"
  for_each = var.create_identity_providers ? var.identity_providers : {}

  cluster_id                            = local.cluster_id
  name                                  = each.value.name
  idp_type                              = each.value.idp_type
  mapping_method                        = try(each.value.mapping_method, null)
  github_idp_client_id                  = try(each.value.github_idp_client_id, null)
  github_idp_client_secret              = try(each.value.github_idp_client_secret, null)
  github_idp_ca                         = try(each.value.github_idp_ca, null)
  github_idp_hostname                   = try(each.value.github_idp_hostname, null)
  github_idp_organizations              = try(each.value.github_idp_organizations, null) == null ? null : (can(jsondecode(each.value.github_idp_organizations)) ? jsondecode(each.value.github_idp_organizations) : each.value.github_idp_organizations)
  github_idp_teams                      = try(each.value.github_idp_teams, null) == null ? null : (can(jsondecode(each.value.github_idp_teams)) ? jsondecode(each.value.github_idp_teams) : each.value.github_idp_teams)
  gitlab_idp_client_id                  = try(each.value.gitlab_idp_client_id, null)
  gitlab_idp_client_secret              = try(each.value.gitlab_idp_client_secret, null)
  gitlab_idp_url                        = try(each.value.gitlab_idp_url, null)
  gitlab_idp_ca                         = try(each.value.gitlab_idp_ca, null)
  google_idp_client_id                  = try(each.value.google_idp_client_id, null)
  google_idp_client_secret              = try(each.value.google_idp_client_secret, null)
  google_idp_hosted_domain              = try(each.value.google_idp_hosted_domain, null)
  htpasswd_idp_users                    = try(each.value.htpasswd_idp_users, null) == null ? null : (can(jsondecode(each.value.htpasswd_idp_users)) ? jsondecode(each.value.htpasswd_idp_users) : each.value.htpasswd_idp_users)
  ldap_idp_bind_dn                      = try(each.value.ldap_idp_bind_dn, null)
  ldap_idp_bind_password                = try(each.value.ldap_idp_bind_password, null)
  ldap_idp_ca                           = try(each.value.ldap_idp_ca, null)
  ldap_idp_insecure                     = try(each.value.ldap_idp_insecure, null)
  ldap_idp_url                          = try(each.value.ldap_idp_url, null)
  ldap_idp_emails                       = try(each.value.ldap_idp_emails, null) == null ? null : (can(jsondecode(each.value.ldap_idp_emails)) ? jsondecode(each.value.ldap_idp_emails) : each.value.ldap_idp_emails)
  ldap_idp_ids                          = try(each.value.ldap_idp_ids, null) == null ? null : (can(jsondecode(each.value.ldap_idp_ids)) ? jsondecode(each.value.ldap_idp_ids) : each.value.ldap_idp_ids)
  ldap_idp_names                        = try(each.value.ldap_idp_names, null) == null ? null : (can(jsondecode(each.value.ldap_idp_names)) ? jsondecode(each.value.ldap_idp_names) : each.value.ldap_idp_names)
  ldap_idp_preferred_usernames          = try(each.value.ldap_idp_preferred_usernames, null) == null ? null : (can(jsondecode(each.value.ldap_idp_preferred_usernames)) ? jsondecode(each.value.ldap_idp_preferred_usernames) : each.value.ldap_idp_preferred_usernames)
  openid_idp_ca                         = try(each.value.openid_idp_ca, null)
  openid_idp_claims_email               = try(each.value.openid_idp_claims_email, null) == null ? null : (can(jsondecode(each.value.openid_idp_claims_email)) ? jsondecode(each.value.openid_idp_claims_email) : each.value.openid_idp_claims_email)
  openid_idp_claims_groups              = try(each.value.openid_idp_claims_groups, null) == null ? null : (can(jsondecode(each.value.openid_idp_claims_groups)) ? jsondecode(each.value.openid_idp_claims_groups) : each.value.openid_idp_claims_groups)
  openid_idp_claims_name                = try(each.value.openid_idp_claims_name, null) == null ? null : (can(jsondecode(each.value.openid_idp_claims_name)) ? jsondecode(each.value.openid_idp_claims_name) : each.value.openid_idp_claims_name)
  openid_idp_claims_preferred_username  = try(each.value.openid_idp_claims_preferred_username, null) == null ? null : (can(jsondecode(each.value.openid_idp_claims_preferred_username)) ? jsondecode(each.value.openid_idp_claims_preferred_username) : each.value.openid_idp_claims_preferred_username)
  openid_idp_client_id                  = try(each.value.openid_idp_client_id, null)
  openid_idp_client_secret              = try(each.value.openid_idp_client_secret, null)
  openid_idp_extra_scopes               = try(each.value.openid_idp_extra_scopes, null) == null ? null : (can(jsondecode(each.value.openid_idp_extra_scopes)) ? jsondecode(each.value.openid_idp_extra_scopes) : each.value.openid_idp_extra_scopes)
  openid_idp_extra_authorize_parameters = try(each.value.openid_idp_extra_authorize_parameters, null) == null ? null : (can(jsondecode(each.value.openid_idp_extra_authorize_parameters)) ? jsondecode(each.value.openid_idp_extra_authorize_parameters) : each.value.openid_idp_extra_authorize_parameters)
  openid_idp_issuer                     = try(each.value.openid_idp_issuer, null)
}

##############################################################
# Kubelet Configurations
##############################################################

module "rhcs_hcp_kubelet_configs" {
  source   = "./modules/kubelet-configs"
  for_each = var.kubelet_configs

  cluster_id     = local.cluster_id
  name           = each.value.name
  pod_pids_limit = each.value.pod_pids_limit
}

##############################################################
# Image Mirrors
##############################################################

module "rhcs_hcp_image_mirrors" {
  source   = "./modules/image-mirrors"
  for_each = var.image_mirrors

  cluster_id      = local.cluster_id
  type            = each.value.type
  source_registry = each.value.source
  mirrors         = each.value.mirrors
}

##############################################################
# Additional Machine Pools
##############################################################

module "rhcs_hcp_machine_pool" {
  source   = "./modules/machine-pool"
  for_each = var.create_additional_machine_pools ? var.machine_pools : {}

  cluster_id = local.cluster_id
  name       = each.value.name

  replicas    = try(each.value.autoscaling, null) != null ? null : try(each.value.replicas, 2)
  auto_repair = try(each.value.auto_repair, true)

  autoscaling = try(each.value.autoscaling, null) != null ? {
    enabled      = true
    min_replicas = try(each.value.autoscaling.min_replicas, 1)
    max_replicas = try(each.value.autoscaling.max_replicas, 5)
    } : {
    enabled      = false
    min_replicas = null
    max_replicas = null
  }

  aws_node_pool = {
    instance_type                 = try(each.value.aws_node_pool.instance_type, try(each.value.instance_type, "m5.xlarge"))
    tags                          = merge(var.tags, try(each.value.aws_node_pool.tags, try(each.value.tags, {})))
    additional_security_group_ids = try(each.value.aws_node_pool.additional_security_group_ids, try(each.value.additional_security_group_ids, null))
    disk_size                     = try(each.value.aws_node_pool.disk_size, try(each.value.disk_size, null))
  }

  subnet_id         = local.machine_pool_selected_subnet_ids[each.key]
  openshift_version = var.openshift_version

  tuning_configs               = try(each.value.tuning_configs, null)
  upgrade_acknowledgements_for = try(each.value.upgrade_acknowledgements_for, null)
  taints                       = try(each.value.taints, null)
  labels                       = try(each.value.labels, null)
  kubelet_configs              = try(each.value.kubelet_configs, null)
  ignore_deletion_error        = try(each.value.ignore_deletion_error, var.ignore_machine_pools_deletion_error)

  depends_on = [module.rosa_cluster_hcp]
}

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
          AWS = "arn:aws:iam::710019948333:root"
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

resource "aws_iam_role_policy_attachment" "ocm_role_policies" {
  count      = var.create_ocm_role ? length(local.ocm_policies) : 0
  role       = aws_iam_role.ocm_role[0].name
  policy_arn = local.ocm_policies[count.index]
}

##############################################################
# Validations
##############################################################

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
# OpenShift GitOps (ArgoCD) Module
##############################################################

module "openshift_gitops" {
  source = "./modules/openshift-gitops"

  enabled                = local.deploy_openshift_gitops
  cluster_id             = local.cluster_id
  cluster_api_url        = local.cluster_api_url
  cluster_admin_username = local.cluster_admin_username
  cluster_admin_password = local.cluster_admin_password

  depends_on = [module.rosa_cluster_hcp]
}

##############################################################
# ArgoCD Applications (Data-Driven using for_each)
##############################################################

module "argocd_applications" {
  source   = "./modules/argocd-application"
  for_each = local.enabled_argocd_applications

  enabled                = true
  cluster_id             = local.cluster_id
  cluster_api_url        = local.cluster_api_url
  cluster_admin_username = local.cluster_admin_username
  cluster_admin_password = local.cluster_admin_password

  application_name      = each.key
  repo_url              = each.value.repo_url
  path                  = each.value.path
  destination_namespace = each.value.namespace
  create_namespace      = lookup(each.value, "create_namespace", true)

  depends_on = [module.openshift_gitops]
}

##############################################################
# GitOps Template Processor Module
##############################################################

module "gitops_template_processor" {
  source = "./modules/gitops-template-processor"

  enabled                        = (var.deploy_keycloak || var.deploy_developerhub) && local.deploy_openshift_gitops
  cluster_id                     = local.cluster_id
  cluster_api_url                = local.cluster_api_url
  cluster_admin_username         = local.cluster_admin_username
  cluster_admin_password         = local.cluster_admin_password
  process_developerhub_templates = var.deploy_developerhub

  depends_on = [module.openshift_gitops]
}

##############################################################
# Keycloak OAuth Client Module
##############################################################

# Generate OIDC client secret
resource "random_password" "oidc_client_secret" {
  count   = var.deploy_keycloak && var.deploy_developerhub ? 1 : 0
  length  = 32
  special = true
}

# Generate session secret
resource "random_password" "session_secret" {
  count   = var.deploy_developerhub ? 1 : 0
  length  = 32
  special = true
}

# Get cluster domain dynamically
data "external" "cluster_domain" {
  count = var.deploy_keycloak || var.deploy_developerhub ? 1 : 0

  depends_on = [module.openshift_gitops]

  program = ["bash", "-c", <<-EOT
    export KUBECONFIG=/tmp/rosa-kubeconfig-$$
    oc login --username="${local.cluster_admin_username}" \
             --password="${local.cluster_admin_password}" \
             "${local.cluster_api_url}" \
             --insecure-skip-tls-verify \
             --kubeconfig=$KUBECONFIG >/dev/null 2>&1
    DOMAIN=$(oc --kubeconfig=$KUBECONFIG get ingress.config.openshift.io/cluster -o jsonpath='{.spec.domain}')
    rm -f $KUBECONFIG
    echo "{\"domain\": \"$DOMAIN\"}"
  EOT
  ]
}

module "keycloak_oauth" {
  source = "./modules/keycloak-oauth"

  enabled                = var.deploy_keycloak && var.deploy_developerhub
  cluster_id             = local.cluster_id
  cluster_api_url        = local.cluster_api_url
  cluster_admin_username = local.cluster_admin_username
  cluster_admin_password = local.cluster_admin_password
  cluster_domain         = local.oauth_cluster_domain
  oidc_client_secret     = var.deploy_keycloak && var.deploy_developerhub ? random_password.oidc_client_secret[0].result : ""
  redirect_uris          = local.devhub_redirect_uris
  web_origins            = local.devhub_web_origins
  keycloak_namespace     = "rhbk"
  keycloak_route_name    = "keycloak"
  keycloak_wait_timeout  = var.keycloak_wait_timeout

  depends_on = [
    module.gitops_template_processor,
    module.argocd_applications
  ]
}
