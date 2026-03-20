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

variable "app_config_template_path" {
  type        = string
  default     = ""
  description = "Path to Developer Hub app-config.yaml.template file."
}

variable "auth_secret_template_path" {
  type        = string
  default     = ""
  description = "Path to Developer Hub auth-secret.yaml.template file."
}

variable "oidc_client_secret" {
  type        = string
  default     = ""
  sensitive   = true
  description = "OIDC client secret for Developer Hub auth secret."
}

variable "session_secret" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Session secret for Developer Hub auth secret."
}

variable "process_agentic_templates" {
  type        = bool
  default     = false
  description = "Render and apply agentic Developer Hub/Dev Spaces templates with cluster-specific values."
}

variable "agentic_template_path" {
  type        = string
  default     = ""
  description = "Path to agentic Developer Hub scaffolder template YAML."
}

variable "agentic_devfile_path" {
  type        = string
  default     = ""
  description = "Path to agentic Dev Spaces factory devfile YAML."
}

variable "agentic_app_config_snippet_path" {
  type        = string
  default     = ""
  description = "Path to Developer Hub app-config agentic snippet YAML."
}

variable "model_api_base" {
  type        = string
  default     = "http://qwen-25-7b-predictor.models.svc.cluster.local:8080/v1"
  description = "OpenAI-compatible API base URL used by Continue and Dev Hub proxy."
}

variable "model_id" {
  type        = string
  default     = "qwen-25-7b"
  description = "Model identifier sent by Developer Hub and Continue."
}
