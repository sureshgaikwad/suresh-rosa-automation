################################################################################
# OpenShift GitOps Module Outputs
################################################################################

output "gitops_installed" {
  value       = var.enabled
  description = "Whether GitOps was installed."
}

output "argocd_namespace" {
  value       = var.enabled ? "openshift-gitops" : null
  description = "Namespace where ArgoCD is installed."
}

output "argocd_ready" {
  value       = var.enabled && var.create_argocd_instance
  description = "Whether ArgoCD instance is ready."
}
