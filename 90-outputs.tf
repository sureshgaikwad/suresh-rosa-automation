##############################################################
# Authentication and IAM Outputs
##############################################################

output "account_role_prefix" {
  value       = var.create_account_roles ? module.account_iam_resources[0].account_role_prefix : null
  description = "The prefix used for all generated AWS resources."
}

output "account_roles_arn" {
  value       = var.create_account_roles ? module.account_iam_resources[0].account_roles_arn : null
  description = "A map of Amazon Resource Names (ARNs) associated with the AWS IAM roles created."
}

output "path" {
  value       = var.create_account_roles ? module.account_iam_resources[0].path : null
  description = "The arn path for the account/operator roles as well as their policies."
}

output "oidc_config_id" {
  value       = var.create_oidc ? module.oidc_config_and_provider[0].oidc_config_id : null
  description = "The unique identifier associated with users authenticated through OpenID Connect (OIDC)."
}

output "oidc_endpoint_url" {
  value       = var.create_oidc ? module.oidc_config_and_provider[0].oidc_endpoint_url : null
  description = "Registered OIDC configuration issuer URL."
}

output "operator_role_prefix" {
  value       = var.create_operator_roles ? module.operator_roles[0].operator_role_prefix : null
  description = "Prefix used for generated AWS operator policies."
}

output "operator_roles_arn" {
  value       = var.create_operator_roles ? module.operator_roles[0].operator_roles_arn : null
  description = "List of Amazon Resource Names (ARNs) for all operator roles created."
}

output "ocm_role_arn" {
  value       = var.create_ocm_role ? aws_iam_role.ocm_role[0].arn : null
  description = "ARN of the OCM (OpenShift Cluster Manager) role"
}

##############################################################
# RHCS Authentication Outputs
##############################################################

output "rhcs_url" {
  description = "Red Hat OpenShift Cluster Manager URL being used"
  value       = var.rhcs_url
}

output "rhcs_authentication_method" {
  description = "RHCS authentication method being used"
  value       = var.rhcs_token != null ? "token" : (var.rhcs_client_id != null ? "client_credentials" : "environment_variables")
}

##############################################################
# Cluster Information Outputs
##############################################################

output "cluster_id" {
  value       = local.cluster_id
  description = "Unique identifier of the cluster."
}

output "cluster_admin_username" {
  value       = local.cluster_admin_username
  description = "The username of the admin user."
}

output "cluster_admin_password" {
  value       = local.cluster_admin_password
  description = "The password of the admin user."
  sensitive   = true
}

output "cluster_api_url" {
  value       = local.cluster_api_url
  description = "The URL of the API server."
}

output "cluster_console_url" {
  value       = local.cluster_console_url
  description = "The URL of the console."
}

output "cluster_domain" {
  value       = local.cluster_domain
  description = "The DNS domain of cluster."
}

output "cluster_current_version" {
  value       = local.cluster_current_version
  description = "The currently running version of OpenShift on the cluster."
}

output "cluster_state" {
  value       = local.cluster_state
  description = "The state of the cluster."
}

##############################################################
# Machine Pools Outputs
##############################################################

output "additional_machine_pools" {
  value = {
    for k, v in module.rhcs_hcp_machine_pool : k => {
      id        = v.machine_pool_id
      name      = v.machine_pool_name
      subnet_id = v.subnet_id
      replicas  = v.replicas
    }
  }
  description = "Map of additional machine pools created"
}

##############################################################
# Image Mirrors Outputs
##############################################################

output "image_mirror_ids" {
  value = {
    for k, v in module.rhcs_hcp_image_mirrors : k => v.image_mirror_id
  }
  description = "A map of image mirror names to their unique identifiers."
}

##############################################################
# VPC and Network Outputs
##############################################################

output "vpc_id" {
  value       = var.create_vpc ? module.vpc[0].vpc_id : null
  description = "ID of the VPC created by the VPC module"
}

output "vpc_cidr" {
  value       = var.create_vpc ? module.vpc[0].cidr_block : null
  description = "CIDR block of the VPC"
}

output "private_subnets" {
  value       = var.create_vpc ? module.vpc[0].private_subnets : var.aws_subnet_ids
  description = "List of private subnet IDs used by the cluster"
}

output "cluster_subnets" {
  value       = local.cluster_subnet_ids
  description = "List of all subnet IDs (public + private) used by the cluster"
}

output "public_subnets" {
  value       = var.create_vpc ? module.vpc[0].public_subnets : null
  description = "List of public subnet IDs created by the VPC module (empty list for zero egress)"
}

output "availability_zones" {
  value       = var.create_vpc ? module.vpc[0].availability_zones : var.aws_availability_zones
  description = "List of availability zones used by the VPC/cluster"
}

##############################################################
# OpenShift GitOps and ArgoCD Outputs
##############################################################

output "openshift_gitops_enabled" {
  description = "Whether OpenShift GitOps operator is deployed"
  value       = module.openshift_gitops.gitops_installed
}

output "argocd_namespace" {
  description = "Namespace where ArgoCD is installed"
  value       = module.openshift_gitops.argocd_namespace
}

output "argocd_server_url" {
  description = "ArgoCD server URL"
  value       = local.deploy_openshift_gitops ? "https://openshift-gitops-server-openshift-gitops.apps.${local.cluster_domain}" : null
}

output "gitops_repo_url" {
  description = "GitOps repository URL configured for ArgoCD"
  value       = local.deploy_openshift_gitops ? var.gitops_repo_url : null
}

##############################################################
# ArgoCD Applications Outputs
##############################################################

output "argocd_applications_config" {
  description = "ArgoCD application configurations for the bootstrap script (scripts/bootstrap-gitops.sh)"
  value = {
    for k, v in local.enabled_argocd_applications : k => {
      repo_url         = v.repo_url
      path             = v.path
      namespace        = v.namespace
      create_namespace = lookup(v, "create_namespace", true)
    }
  }
}

output "argocd_applications_deployed" {
  description = "Map of ArgoCD applications that were deployed via Terraform"
  value = {
    for k, v in module.argocd_applications : k => {
      name      = v.application_name
      namespace = v.application_namespace
    }
  }
}

output "vote_application_enabled" {
  description = "Whether vote application is deployed via ArgoCD"
  value       = contains(keys(local.enabled_argocd_applications), "vote-app")
}

output "openshift_ai_enabled" {
  description = "Whether OpenShift AI operator is deployed via ArgoCD"
  value       = contains(keys(local.enabled_argocd_applications), "openshift-ai-operator")
}

output "openshift_serverless_enabled" {
  description = "Whether OpenShift Serverless operator is deployed via ArgoCD"
  value       = contains(keys(local.enabled_argocd_applications), "openshift-serverless-operator")
}

output "openshift_servicemesh_enabled" {
  description = "Whether OpenShift Service Mesh operator is deployed via ArgoCD"
  value       = contains(keys(local.enabled_argocd_applications), "openshift-servicemesh-operator")
}

output "nfd_gitops_enabled" {
  description = "Whether NodeFileDiscovery operator is deployed via ArgoCD"
  value       = contains(keys(local.enabled_argocd_applications), "nfd-gitops")
}

output "nvidia_gpu_operator_gitops_enabled" {
  description = "Whether NVIDIA GPU operator is deployed via ArgoCD"
  value       = contains(keys(local.enabled_argocd_applications), "nvidia-gpu-operator-gitops")
}

output "authorino_operator_enabled" {
  description = "Whether Authorino operator is deployed via ArgoCD"
  value       = contains(keys(local.enabled_argocd_applications), "authorino-operator")
}

output "ai_model_enabled" {
  description = "Whether AI model is deployed via ArgoCD"
  value       = contains(keys(local.enabled_argocd_applications), "ai-model")
}

##############################################################
# GitOps Template Processing Outputs
##############################################################

output "gitops_templates_processed" {
  value       = module.gitops_template_processor.templates_processed
  description = "Status of GitOps template processing"
}

##############################################################
# Keycloak OAuth Outputs
##############################################################

output "keycloak_oauth_client_id" {
  value       = var.deploy_keycloak && var.deploy_developerhub ? module.keycloak_oauth.client_id : null
  description = "Keycloak OAuth client ID"
}

output "oidc_client_secret" {
  value       = var.deploy_keycloak && var.deploy_developerhub ? random_password.oidc_client_secret[0].result : ""
  sensitive   = true
  description = "OIDC client secret for Developer Hub"
}

output "session_secret" {
  value       = var.deploy_developerhub ? random_password.session_secret[0].result : ""
  sensitive   = true
  description = "Session secret for Developer Hub"
}
