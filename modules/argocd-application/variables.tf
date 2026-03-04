################################################################################
# ArgoCD Application Module Variables
################################################################################

variable "enabled" {
  type        = bool
  default     = true
  description = "Enable application creation."
}

variable "cluster_id" {
  type        = string
  description = "ROSA cluster ID."
}

variable "cluster_api_url" {
  type        = string
  description = "Cluster API URL."
}

variable "cluster_admin_username" {
  type        = string
  description = "Cluster admin username."
}

variable "cluster_admin_password" {
  type        = string
  sensitive   = true
  description = "Cluster admin password."
}

variable "application_name" {
  type        = string
  description = "Name of the ArgoCD application."
}

variable "argocd_namespace" {
  type        = string
  default     = "openshift-gitops"
  description = "Namespace where ArgoCD is installed."
}

variable "project" {
  type        = string
  default     = "default"
  description = "ArgoCD project."
}

variable "repo_url" {
  type        = string
  description = "Git repository URL."
}

variable "target_revision" {
  type        = string
  default     = "HEAD"
  description = "Git revision (branch, tag, commit)."
}

variable "path" {
  type        = string
  description = "Path within the repository."
}

variable "destination_server" {
  type        = string
  default     = "https://kubernetes.default.svc"
  description = "Destination Kubernetes API server."
}

variable "destination_namespace" {
  type        = string
  description = "Destination namespace for the application."
}

variable "auto_prune" {
  type        = bool
  default     = true
  description = "Enable automatic pruning."
}

variable "self_heal" {
  type        = bool
  default     = true
  description = "Enable self-healing."
}

variable "create_namespace" {
  type        = bool
  default     = true
  description = "Create destination namespace if it doesn't exist."
}

variable "retry_limit" {
  type        = number
  default     = 5
  description = "Number of sync retries."
}
