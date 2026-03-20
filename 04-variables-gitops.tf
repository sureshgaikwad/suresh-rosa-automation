##############################################################
# OpenShift Features and Operators
##############################################################

variable "deploy_openshift_gitops" {
  type        = bool
  default     = false
  description = "Deploy OpenShift GitOps operator via Terraform (requires network access to cluster API). Set to false and use scripts/bootstrap-gitops.sh instead for private/zero-egress clusters."
}

variable "deploy_vote_application" {
  type        = bool
  default     = true
  description = "Deploy vote application using ArgoCD"
}

variable "deploy_openshift_ai" {
  type        = bool
  default     = false
  description = "Deploy OpenShift AI operator via ArgoCD application"
}

variable "deploy_openshift_serverless" {
  type        = bool
  default     = false
  description = "Deploy OpenShift Serverless operator via ArgoCD application"
}

variable "deploy_ai_model" {
  type        = bool
  default     = false
  description = "Deploy AI model using ArgoCD"
}

variable "deploy_nvidia_gpu_operator" {
  type        = bool
  default     = false
  description = "Deploy NVIDIA GPU operator via ArgoCD"
}

variable "deploy_openshift_servicemesh" {
  type        = bool
  default     = false
  description = "Deploy OpenShift Service Mesh operator via ArgoCD application"
}

variable "deploy_kueue_operator" {
  type        = bool
  default     = false
  description = "Deploy Kueue operator via ArgoCD using gitops-catalog repository"
}

variable "deploy_jobset_operator" {
  type        = bool
  default     = false
  description = "Deploy JobSet operator via ArgoCD using gitops-catalog repository"
}

variable "deploy_cert_manager_operator" {
  type        = bool
  default     = false
  description = "Deploy cert-manager operator via ArgoCD using gitops-catalog repository"
}

variable "deploy_nfd_application" {
  type        = bool
  default     = false
  description = "Deploy NodeFileDiscovery operator via ArgoCD using gitops-catalog repository"
}

variable "deploy_nvidia_gpu_operator_application" {
  type        = bool
  default     = false
  description = "Deploy NVIDIA GPU operator via ArgoCD using gitops-catalog repository"
}

variable "deploy_openshift_lightspeed" {
  type        = bool
  default     = false
  description = "Deploy OpenShift Lightspeed operator via ArgoCD using gitops-catalog repository"
}

variable "deploy_authorino_operator" {
  type        = bool
  default     = false
  description = "Deploy Authorino operator via ArgoCD using gitops-catalog repository"
}

variable "deploy_nfd" {
  type    = bool
  default = true
}

variable "deploy_gpu_operator" {
  type    = bool
  default = true
}

variable "deploy_keycloak" {
  type        = bool
  default     = false
  description = "Deploy Keycloak operator and instance via ArgoCD using gitops-catalog repository"
}

variable "keycloak_wait_timeout" {
  type        = number
  default     = 600
  description = "Seconds to wait for Keycloak to become ready before failing. Increase if Keycloak pod starts slowly (e.g. 900 for first-time deploy)."
}

variable "deploy_developerhub" {
  type        = bool
  default     = false
  description = "Deploy Red Hat Developer Hub operator and instance via ArgoCD using gitops-catalog repository"
}

variable "keycloak_bootstrap_user_enabled" {
  type        = bool
  default     = true
  description = "Create/update a bootstrap Keycloak user for Developer Hub OIDC login."
}

variable "keycloak_bootstrap_username" {
  type        = string
  default     = "test"
  description = "Bootstrap Keycloak username for Developer Hub login."
}

variable "keycloak_bootstrap_email" {
  type        = string
  default     = "test@gmail.com"
  description = "Bootstrap Keycloak user email. Must match Backstage user entity email."
}

variable "keycloak_bootstrap_first_name" {
  type        = string
  default     = "Test"
  description = "Bootstrap Keycloak user first name."
}

variable "keycloak_bootstrap_last_name" {
  type        = string
  default     = "User"
  description = "Bootstrap Keycloak user last name."
}

variable "keycloak_bootstrap_password" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Bootstrap Keycloak user password. If empty, Terraform generates one."
}

variable "keycloak_bootstrap_password_temporary" {
  type        = bool
  default     = false
  description = "Whether bootstrap Keycloak user password is temporary."
}

variable "deploy_openshift_devspaces" {
  type        = bool
  default     = false
  description = "Deploy OpenShift Dev Spaces operator via ArgoCD"
}

variable "deploy_openshift_virtualization" {
  type        = bool
  default     = false
  description = "Deploy OpenShift Virtualization operator via ArgoCD"
}

variable "deploy_web_terminal" {
  type        = bool
  default     = false
  description = "Deploy Web Terminal operator via ArgoCD"
}

variable "deploy_advance_cluster_management" {
  type        = bool
  default     = false
  description = "Deploy Advanced Cluster Management (ACM) operator via ArgoCD"
}

variable "agentic_model_api_base" {
  type        = string
  default     = "http://qwen-25-7b-predictor.models.svc.cluster.local:8080/v1"
  description = "OpenAI-compatible API base URL injected into Dev Spaces Continue config and Developer Hub proxy."
}

variable "agentic_model_id" {
  type        = string
  default     = "qwen-25-7b"
  description = "Model identifier injected into agentic templates and Developer Hub proxy headers."
}

##############################################################
# GitOps Configuration
##############################################################

variable "gitops_repo_url" {
  type        = string
  default     = "https://github.com/sureshgaikwad/gitops-catalog"
  description = "GitOps repository URL for ArgoCD applications"
}

variable "application_repo_path" {
  type        = string
  default     = "gitops-catalog/vote-application"
  description = "Path in the GitOps repository for ArgoCD applications"
}

##############################################################
# Operator Configuration
##############################################################

variable "nfd_namespace" {
  type    = string
  default = "openshift-nfd"
}

variable "nfd_channel" {
  type    = string
  default = "stable"
}

variable "nfd_package_name" {
  type    = string
  default = "node-feature-discovery"
}

variable "gpu_namespace" {
  type    = string
  default = "nvidia-gpu-operator"
}

variable "gpu_channel" {
  type    = string
  default = "stable"
}

variable "gpu_operator_package" {
  type        = string
  default     = "nvidia-gpu-operator"
  description = "Operator package name as appears on OperatorHub; verify and override if needed"
}

variable "oc_cmd" {
  type        = string
  default     = "oc"
  description = "kube CLI command - useful if a different oc/kubectl binary is required"
}

variable "csv_wait_retries" {
  type        = number
  default     = 30
  description = "polling configuration for CSV wait"
}

variable "csv_wait_sleep_seconds" {
  type    = number
  default = 20
}
