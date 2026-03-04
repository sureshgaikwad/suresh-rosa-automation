################################################################################
# ArgoCD Application Module Outputs
################################################################################

output "application_name" {
  value       = var.enabled ? var.application_name : null
  description = "Name of the created ArgoCD application."
}

output "application_namespace" {
  value       = var.enabled ? var.destination_namespace : null
  description = "Destination namespace of the application."
}
