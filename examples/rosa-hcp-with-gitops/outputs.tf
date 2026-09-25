output "openshift_gitops_enabled" {
  value       = module.openshift_gitops.gitops_installed
  description = "Whether OpenShift GitOps operator is deployed"
}

output "argocd_namespace" {
  value       = module.openshift_gitops.argocd_namespace
  description = "Namespace where ArgoCD is installed"
}

output "argocd_server_url" {
  # oauth_cluster_domain is the apps ingress domain (already includes apps.rosa....).
  value       = local.deploy_openshift_gitops && local.oauth_cluster_domain != "" ? "https://openshift-gitops-server-openshift-gitops.${local.oauth_cluster_domain}" : null
  description = "ArgoCD server URL"
}

output "argocd_applications_deployed" {
  value = {
    for k, v in module.argocd_applications : k => {
      name      = v.application_name
      namespace = v.application_namespace
    }
  }
}

output "gitops_templates_processed" {
  value       = module.gitops_template_processor.templates_processed
  description = "Status of GitOps template processing"
}
