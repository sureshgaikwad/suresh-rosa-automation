################################################################################
# GitOps Template Processor Module Outputs
################################################################################

output "templates_processed" {
  value       = var.enabled ? "Templates processed successfully" : "Template processing disabled"
  description = "Status of template processing"
}
