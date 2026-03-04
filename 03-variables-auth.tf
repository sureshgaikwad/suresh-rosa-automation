##############################################################
# Authentication and Authorization Variables
##############################################################

variable "path" {
  type        = string
  default     = "/"
  description = "The arn path for the account/operator roles as well as their policies. Must begin and end with '/'."

  validation {
    condition     = can(regex("^/.*/$", var.path)) || var.path == "/"
    error_message = "Path must begin and end with '/'."
  }
}

variable "permissions_boundary" {
  type        = string
  default     = ""
  description = "The ARN of the policy that is used to set the permissions boundary for the IAM roles in STS clusters."
}

##############################################################
# Account Roles Configuration
##############################################################

variable "create_account_roles" {
  type        = bool
  default     = false
  description = "Create the aws account roles for rosa"
}

variable "account_role_prefix" {
  type        = string
  default     = null
  description = "User-defined prefix for all generated AWS resources (default \"account-role-<random>\")"
}

##############################################################
# OIDC Configuration
##############################################################

variable "create_oidc" {
  description = "Create the oidc resources. This value should not be updated, please create a new resource instead or utilize the submodule to create a new oidc config"
  type        = bool
  default     = false
}

variable "managed_oidc" {
  description = "OIDC type managed or unmanaged oidc. Only active when create_oidc also enabled. This value should not be updated, please create a new resource instead"
  type        = bool
  default     = true
}

variable "oidc_config_id" {
  type        = string
  default     = null
  description = "The unique identifier associated with users authenticated through OpenID Connect (OIDC) within the ROSA cluster. If create_oidc is false this attribute is required."
}

variable "oidc_endpoint_url" {
  type        = string
  default     = null
  description = "Registered OIDC configuration issuer URL, added as the trusted relationship to the operator roles. Valid only when create_oidc is false."
}

##############################################################
# Operator Roles Configuration
##############################################################

variable "create_operator_roles" {
  description = "Create the aws account roles for rosa"
  type        = bool
  default     = false
}

variable "operator_role_prefix" {
  type        = string
  default     = null
  description = "User-defined prefix for generated AWS operator policies. Use \"account-role-prefix\" in case no value provided."
}

##############################################################
# Identity Providers Configuration
##############################################################

variable "create_identity_providers" {
  type        = bool
  default     = false
  description = "Create identity providers for the cluster"
}

variable "identity_providers" {
  type = map(object({
    name     = string
    idp_type = string

    mapping_method = optional(string)

    # GitHub
    github_idp_client_id     = optional(string)
    github_idp_client_secret = optional(string)
    github_idp_ca            = optional(string)
    github_idp_hostname      = optional(string)
    # Accept either native types (list(string)) or legacy JSON-encoded strings.
    github_idp_organizations = optional(any)
    github_idp_teams         = optional(any)

    # GitLab
    gitlab_idp_client_id     = optional(string)
    gitlab_idp_client_secret = optional(string)
    gitlab_idp_url           = optional(string)
    gitlab_idp_ca            = optional(string)

    # Google
    google_idp_client_id     = optional(string)
    google_idp_client_secret = optional(string)
    google_idp_hosted_domain = optional(string)

    # HTPasswd (accept list(object) or JSON string)
    htpasswd_idp_users = optional(any)

    # LDAP
    ldap_idp_bind_dn             = optional(string)
    ldap_idp_bind_password       = optional(string)
    ldap_idp_ca                  = optional(string)
    ldap_idp_insecure            = optional(bool)
    ldap_idp_url                 = optional(string)
    ldap_idp_emails              = optional(any)
    ldap_idp_ids                 = optional(any)
    ldap_idp_names               = optional(any)
    ldap_idp_preferred_usernames = optional(any)

    # OpenID
    openid_idp_ca                         = optional(string)
    openid_idp_claims_email               = optional(any)
    openid_idp_claims_groups              = optional(any)
    openid_idp_claims_name                = optional(any)
    openid_idp_claims_preferred_username  = optional(any)
    openid_idp_client_id                  = optional(string)
    openid_idp_client_secret              = optional(string)
    openid_idp_extra_scopes               = optional(any)
    openid_idp_extra_authorize_parameters = optional(any)
    openid_idp_issuer                     = optional(string)
  }))
  default     = {}
  description = "Map of identity provider configurations. Supports native list/map/object values; legacy JSON-encoded strings are also accepted for non-primitive fields."
}

##############################################################
# OCM Role Configuration
##############################################################

variable "create_ocm_role" {
  type        = bool
  default     = false
  description = "Create OCM (OpenShift Cluster Manager) role"
}

variable "ocm_role_name" {
  type        = string
  default     = "ManagedOpenShift-OCM-Role"
  description = "Name for the OCM role"
}

##############################################################
# Red Hat Cloud Services (RHCS) Authentication
##############################################################

variable "rhcs_client_id" {
  type        = string
  default     = null
  description = "RHCS Client ID for authenticating with Red Hat OpenShift Cluster Manager (OCM). Can also be set via RHCS_CLIENT_ID environment variable."
  sensitive   = true
}

variable "rhcs_client_secret" {
  type        = string
  default     = null
  description = "RHCS Client Secret for authenticating with Red Hat OpenShift Cluster Manager (OCM). Can also be set via RHCS_CLIENT_SECRET environment variable."
  sensitive   = true
}

variable "rhcs_url" {
  type        = string
  default     = "https://api.openshift.com"
  description = "Red Hat OpenShift Cluster Manager URL. Default is production OCM."
}

variable "rhcs_token" {
  type        = string
  default     = null
  sensitive   = true
  description = "RHCS Token for authenticating with Red Hat OpenShift Cluster Manager (OCM). Can also be set via RHCS_TOKEN environment variable."
}
