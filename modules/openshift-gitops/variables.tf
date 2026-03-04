################################################################################
# OpenShift GitOps Module Variables
################################################################################

variable "enabled" {
  type        = bool
  default     = true
  description = "Enable GitOps installation."
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

variable "gitops_channel" {
  type        = string
  default     = "gitops-1.14"
  description = "GitOps operator channel."
}

variable "create_argocd_instance" {
  type        = bool
  default     = true
  description = "Create ArgoCD instance after operator installation."
}

variable "cluster_wait_duration" {
  type        = string
  default     = "120s"
  description = "Time to wait for cluster readiness."
}

variable "node_wait_timeout" {
  type        = number
  default     = 300
  description = "Timeout in seconds for node readiness."
}

variable "operator_wait_duration" {
  type        = string
  default     = "120s"
  description = "Time to wait for operator installation."
}

variable "argocd_wait_duration" {
  type        = string
  default     = "120s"
  description = "Time to wait for ArgoCD to be ready."
}
