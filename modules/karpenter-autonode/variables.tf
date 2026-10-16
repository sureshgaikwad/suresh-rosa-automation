variable "cluster_name" {
  type        = string
  description = "ROSA cluster name used in IAM role naming and tags."
}

variable "oidc_endpoint_url" {
  type        = string
  description = "OIDC issuer host/path without https:// (e.g. oidc.op1.openshiftapps.com/<id>)."
}

variable "role_name" {
  type        = string
  default     = null
  description = "Optional IAM role name. Defaults to rosa-karpenter-controller-role-<cluster_name>."
}

variable "permissions_boundary" {
  type        = string
  default     = null
  description = "Optional IAM permissions boundary ARN."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags for the Karpenter IAM role."
}

variable "path" {
  type        = string
  default     = "/"
  description = "IAM path for the role."
}
