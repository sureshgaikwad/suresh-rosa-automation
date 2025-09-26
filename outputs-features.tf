##############################################################
# OpenShift Features and Operators Outputs
##############################################################

## OpenShift GitOps Outputs

output "openshift_gitops_enabled" {
  description = "Whether OpenShift GitOps operator is deployed"
  value       = var.deploy_openshift_gitops
}

output "vote_application_enabled" {
  description = "Whether vote application is deployed via ArgoCD"
  value       = var.deploy_vote_application && var.deploy_openshift_gitops
}

output "gitops_repo_url" {
  description = "GitOps repository URL configured for ArgoCD"
  value       = var.deploy_vote_application && var.deploy_openshift_gitops ? var.gitops_repo_url : null
}

output "argocd_server_url" {
  description = "ArgoCD server URL (available when vote application is deployed)"
  value       = var.deploy_vote_application && var.deploy_openshift_gitops ? "https://openshift-gitops-server-openshift-gitops.apps.${module.rosa_cluster_hcp.cluster_domain}" : null
}

## Operator Deployment Outputs

output "openshift_ai_enabled" {
  description = "Whether OpenShift AI operator is deployed via ArgoCD"
  value       = var.deploy_openshift_ai && var.deploy_openshift_gitops
}

output "openshift_serverless_enabled" {
  description = "Whether OpenShift Serverless operator is deployed via ArgoCD"
  value       = local.deploy_openshift_serverless && var.deploy_openshift_gitops
}

output "openshift_servicemesh_enabled" {
  description = "Whether OpenShift Service Mesh operator is deployed via ArgoCD"
  value       = local.deploy_openshift_servicemesh && var.deploy_openshift_gitops
}

output "nfd_gitops_enabled" {
  description = "Whether NodeFileDiscovery operator is deployed via ArgoCD using GitOps catalog"
  value       = local.deploy_nfd_application && var.deploy_openshift_gitops
}

output "nvidia_gpu_operator_gitops_enabled" {
  description = "Whether NVIDIA GPU operator is deployed via ArgoCD using GitOps catalog"
  value       = local.deploy_nvidia_gpu_operator_application && var.deploy_openshift_gitops
}

output "openshift_lightspeed_enabled" {
  description = "Whether OpenShift Lightspeed operator is deployed via ArgoCD using GitOps catalog"
  value       = local.deploy_openshift_lightspeed && var.deploy_openshift_gitops
}

output "authorino_operator_enabled" {
  description = "Whether Authorino operator is deployed via ArgoCD using GitOps catalog"
  value       = var.deploy_authorino_operator && var.deploy_openshift_gitops
}

output "ai_model_enabled" {
  description = "Whether AI model is deployed via ArgoCD"
  value       = var.deploy_ai_model && var.deploy_openshift_gitops
}

output "openshift_ai_application_enabled" {
  description = "Whether OpenShift AI operator application is deployed via ArgoCD"
  value       = var.deploy_openshift_ai && var.deploy_openshift_gitops
}