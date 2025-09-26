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
  type        = map(any)
  default     = {}
  description = "Provides a generic approach to add multiple identity providers after the creation of the cluster. This variable allows users to specify configurations for multiple identity providers in a flexible and customizable manner, facilitating the management of resources post-cluster deployment. For additional details regarding the variables utilized, refer to the [idp sub-module](./modules/idp). For non-primitive variables (such as maps, lists, and objects), supply the JSON-encoded string."
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