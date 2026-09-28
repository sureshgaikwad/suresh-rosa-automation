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

variable "dependency_weight" {
  type        = number
  default     = null
  description = "Optional sync-wave weight applied as argocd.argoproj.io/sync-wave on the Application."
}

variable "kustomize_components" {
  type        = list(string)
  default     = []
  description = "Optional Kustomize components (paths relative to the application path)."
}

variable "kustomize_patches" {
  type = list(object({
    target = optional(object({
      group               = optional(string)
      version             = optional(string)
      kind                = optional(string)
      name                = optional(string)
      namespace           = optional(string)
      label_selector      = optional(string)
      annotation_selector = optional(string)
    }))
    patch = optional(string)
    path  = optional(string)
  }))
  default     = []
  description = "Optional Argo CD kustomize patches (inline patch YAML/JSON or path)."
}

variable "kustomize_images" {
  type        = list(string)
  default     = []
  description = "Optional kustomize image overrides (e.g. name=newname:tag)."
}

variable "kustomize_common_annotations" {
  type        = map(string)
  default     = {}
  description = "Optional commonAnnotations merged into all rendered resources."
}

variable "helm_parameters" {
  type = list(object({
    name  = string
    value = string
  }))
  default     = []
  description = "Optional Helm parameters when the source is a Helm chart."
}

variable "helm_values" {
  type        = string
  default     = ""
  description = "Optional inline Helm values YAML."
}

variable "use_helm" {
  type        = bool
  default     = false
  description = "When true, configure source.helm instead of source.kustomize."
}

variable "sync_options" {
  type        = list(string)
  default     = []
  description = "Extra syncOptions appended to the Application syncPolicy."
}
