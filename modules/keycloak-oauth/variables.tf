################################################################################
# Keycloak OAuth Module Variables
################################################################################

variable "enabled" {
  type        = bool
  default     = true
  description = "Enable or disable the Keycloak OAuth client creation"
}

variable "cluster_id" {
  type        = string
  description = "The ROSA cluster ID"
}

variable "cluster_api_url" {
  type        = string
  description = "The API URL of the ROSA cluster"
}

variable "cluster_admin_username" {
  type        = string
  description = "Cluster admin username"
}

variable "cluster_admin_password" {
  type        = string
  sensitive   = true
  description = "Cluster admin password"
}

variable "cluster_domain" {
  type        = string
  description = "The cluster domain (e.g., apps.cluster.example.com)"
}

variable "oidc_client_secret" {
  type        = string
  sensitive   = true
  description = "The OIDC client secret"
}

# Keycloak Configuration
variable "keycloak_namespace" {
  type        = string
  default     = "rhbk"
  description = "Namespace where Keycloak is deployed"
}

variable "keycloak_route_name" {
  type        = string
  default     = "keycloak"
  description = "Name of the Keycloak route"
}

variable "keycloak_realm" {
  type        = string
  default     = "myrealm"
  description = "Keycloak realm to create the client in"
}

variable "keycloak_admin_secret_names" {
  type        = string
  default     = "sample-kc-initial-admin keycloak-initial-admin initial-admin"
  description = "Space-separated list of possible Keycloak admin secret names"
}

# Client Configuration
variable "client_id" {
  type        = string
  default     = "myclient"
  description = "OAuth client ID"
}

variable "client_name" {
  type        = string
  default     = "Developer Hub Client"
  description = "OAuth client display name"
}

variable "client_description" {
  type        = string
  default     = "OIDC client for Red Hat Developer Hub authentication"
  description = "OAuth client description"
}

variable "redirect_uris" {
  type        = list(string)
  description = "List of allowed redirect URIs for the OAuth client"
}

variable "web_origins" {
  type        = list(string)
  description = "List of allowed web origins for the OAuth client"
}

# Timeouts
variable "keycloak_wait_timeout" {
  type        = number
  default     = 600
  description = "Maximum time to wait for Keycloak to be ready (seconds). Keycloak first boot can take 5+ minutes; increase if ArgoCD sync or pod startup is slow."
}

variable "realm_wait_timeout" {
  type        = number
  default     = 600
  description = "Maximum time to wait for the realm to be created (seconds)"
}
