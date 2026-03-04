################################################################################
# Keycloak OAuth Module Outputs
################################################################################

output "client_id" {
  value       = var.client_id
  description = "The OAuth client ID"
}

output "keycloak_realm" {
  value       = var.keycloak_realm
  description = "The Keycloak realm where the client was created"
}

output "oauth_client_created" {
  value       = var.enabled
  description = "Whether the OAuth client was created"
}
