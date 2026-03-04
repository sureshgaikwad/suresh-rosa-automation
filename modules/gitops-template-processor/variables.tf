################################################################################
# GitOps Template Processor Module Variables
################################################################################

variable "enabled" {
  type        = bool
  default     = true
  description = "Enable or disable template processing"
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

variable "process_developerhub_templates" {
  type        = bool
  default     = false
  description = "Process Developer Hub configuration and apply it directly to the cluster"
}

variable "devhub_namespace" {
  type        = string
  default     = "demo-project"
  description = "Namespace where Developer Hub is deployed"
}

variable "force_update" {
  type        = bool
  default     = false
  description = "Force template reprocessing on every apply"
}
