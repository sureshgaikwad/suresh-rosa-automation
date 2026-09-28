# Copyright Red Hat
# SPDX-License-Identifier: Apache-2.0

variable "aws_region" {
  type        = string
  description = "AWS region of the cluster"
}

variable "cluster_id" {
  type        = string
  description = "OCM cluster ID from the deployed ROSA stack (terraform output -raw cluster_id)"
}

variable "cluster_api_url" {
  type        = string
  description = "Cluster API URL (terraform output -raw cluster_api_url)"
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
  default     = ""
  description = "Optional cluster DNS domain. When empty, discovered via oc after GitOps is installed."
}

variable "deploy_openshift_gitops" {
  type        = bool
  default     = true
  description = "Deploy OpenShift GitOps operator via Terraform"
}

variable "deploy_vote_application" {
  type        = bool
  default     = true
  description = "Deploy vote application using ArgoCD"
}

variable "deploy_openshift_ai" {
  type        = bool
  default     = false
  description = "Deploy OpenShift AI (RHOAI) via GitOps. Fans out NFD, GPU, Serverless, Kueue, JobSet, cert-manager."
}

variable "deploy_rhoai_maas" {
  type        = bool
  default     = false
  description = "Deploy RHOAI Models-as-a-Service stack (RHCL, LWS, gateway, postgres). Implies deploy_openshift_ai."
}

variable "deploy_rhoai_llmd" {
  type        = bool
  default     = false
  description = "Deploy llm-d serving + KEDA autoscaling. Implies deploy_rhoai_maas."
}

variable "deploy_rhoai_maas_sample_model" {
  type        = bool
  default     = true
  description = "When deploy_rhoai_maas is true, also sync the sample LLMInferenceService + MaaS governance CRs."
}

variable "deploy_rhoai_llmd_keda" {
  type        = bool
  default     = true
  description = "When deploy_rhoai_llmd is true, also sync the KEDA ScaledObject component."
}

variable "rhoai_channel" {
  type        = string
  default     = "stable-3.5"
  description = "OLM channel for the rhods-operator Subscription."
}

variable "rhoai_genai_backend" {
  type        = string
  default     = "ogx"
  description = "Gen AI backend component: ogx (RHOAI 3.5 Gen AI Studio) or llamastack."

  validation {
    condition     = contains(["ogx", "llamastack"], var.rhoai_genai_backend)
    error_message = "rhoai_genai_backend must be \"ogx\" or \"llamastack\"."
  }
}

variable "rhoai_maas_hostname" {
  type        = string
  default     = ""
  description = "MaaS gateway hostname. Empty = maas.<cluster_domain>."
}

variable "rhoai_maas_tls_secret_name" {
  type        = string
  default     = ""
  description = "TLS secret in openshift-ingress for the MaaS Gateway. Empty = auto-detect IngressController defaultCertificate (ROSA) or fall back to maas-gateway-tls."
}

variable "rhoai_maas_model_name" {
  type        = string
  default     = "qwen25-05b-maas"
  description = "Name for the sample MaaS LLMInferenceService / MaaSModelRef."
}

variable "rhoai_maas_model_namespace" {
  type        = string
  default     = "rhoai-deploy"
  description = "Namespace for MaaS / llm-d sample models."
}

variable "rhoai_maas_model_display_name" {
  type        = string
  default     = "qwen25-05b"
  description = "OpenAI model id (spec.model.name) for the sample MaaS service."
}

variable "rhoai_maas_model_oci_uri" {
  type        = string
  default     = "oci://quay.io/redhat-ai-services/modelcar-catalog:qwen2.5-0.5b-instruct"
  description = "OCI modelcar URI for the sample MaaS model."
}

variable "rhoai_maas_vllm_image" {
  type        = string
  # registry.redhat.io rejects :latest for this repo; pin to the RHOAI 3.5 digest.
  default     = "registry.redhat.io/rhaii/vllm-cpu-rhel9@sha256:7a28b867955055a8836ea2a78e70b8bad63c1ee50e8a5f8dd95d1194f20ec489"
  description = "vLLM CPU container image for sample MaaS / llm-d workloads (must be a digest or explicit tag)."
}

variable "rhoai_maas_token_rate_limit" {
  type        = string
  default     = "100"
  description = "Token rate limit for the sample MaaS subscription."
}

variable "rhoai_maas_token_rate_window" {
  type        = string
  default     = "1m"
  description = "Token rate window for the sample MaaS subscription."
}

variable "rhoai_maas_postgres_storage_size" {
  type        = string
  default     = "5Gi"
  description = "PVC size for MaaS PostgreSQL."
}

variable "rhoai_maas_postgres_image" {
  type        = string
  default     = "registry.redhat.io/rhel9/postgresql-15:latest"
  description = "PostgreSQL image for MaaS."
}

variable "rhoai_maas_postgres_user" {
  type        = string
  default     = "maas"
  description = "PostgreSQL user for MaaS (written into cluster secrets, not git)."
}

variable "rhoai_maas_postgres_database" {
  type        = string
  default     = "maas"
  description = "PostgreSQL database name for MaaS."
}

variable "rhoai_maas_postgres_password" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Optional PostgreSQL password. Empty = auto-generate."
}

variable "rhoai_llmd_model_name" {
  type        = string
  default     = "qwen25-05b-llmd"
  description = "Name for the llm-d LLMInferenceService."
}

variable "rhoai_llmd_model_oci_uri" {
  type        = string
  default     = "oci://quay.io/redhat-ai-services/modelcar-catalog:qwen2.5-0.5b-instruct"
  description = "OCI modelcar URI for the llm-d sample model."
}

variable "rhoai_llmd_keda_min_replicas" {
  type        = string
  default     = "0"
  description = "KEDA ScaledObject minReplicaCount (0 keeps llm-d idle so the MaaS sample can schedule on small CPU pools)."
}

variable "rhoai_llmd_keda_max_replicas" {
  type        = string
  default     = "4"
  description = "KEDA ScaledObject maxReplicaCount."
}

variable "rhoai_llmd_keda_threshold" {
  type        = string
  default     = "5"
  description = "KEDA Prometheus threshold for num_requests_waiting."
}

variable "deploy_openshift_serverless" {
  type    = bool
  default = false
}

variable "deploy_ai_model" {
  type    = bool
  default = false
}

variable "deploy_nvidia_gpu_operator" {
  type    = bool
  default = false
}

variable "deploy_openshift_servicemesh" {
  type    = bool
  default = false
}

variable "deploy_kueue_operator" {
  type    = bool
  default = false
}

variable "deploy_jobset_operator" {
  type    = bool
  default = false
}

variable "deploy_cert_manager_operator" {
  type    = bool
  default = false
}

variable "deploy_cluster_observability_operator" {
  type        = bool
  default     = false
  description = "Deploy Cluster Observability Operator. Auto-enabled when deploy_rhoai_maas / deploy_rhoai_llmd is true."
}

variable "deploy_opentelemetry_operator" {
  type        = bool
  default     = false
  description = "Deploy OpenTelemetry operator. Auto-enabled when deploy_rhoai_maas / deploy_rhoai_llmd is true."
}

variable "deploy_nfd_application" {
  type    = bool
  default = false
}

variable "deploy_nvidia_gpu_operator_application" {
  type    = bool
  default = false
}

variable "deploy_openshift_lightspeed" {
  type    = bool
  default = false
}

variable "deploy_authorino_operator" {
  type    = bool
  default = false
}

variable "deploy_nfd" {
  type    = bool
  default = true
}

variable "deploy_keycloak" {
  type    = bool
  default = false
}

variable "keycloak_wait_timeout" {
  type    = number
  default = 600
}

variable "deploy_developerhub" {
  type    = bool
  default = false
}

variable "keycloak_bootstrap_user_enabled" {
  type    = bool
  default = true
}

variable "keycloak_bootstrap_username" {
  type    = string
  default = "test"
}

variable "keycloak_bootstrap_email" {
  type    = string
  default = "test@gmail.com"
}

variable "keycloak_bootstrap_first_name" {
  type    = string
  default = "Test"
}

variable "keycloak_bootstrap_last_name" {
  type    = string
  default = "User"
}

variable "keycloak_bootstrap_password" {
  type      = string
  default   = ""
  sensitive = true
}

variable "keycloak_bootstrap_password_temporary" {
  type    = bool
  default = false
}

variable "deploy_openshift_devspaces" {
  type    = bool
  default = false
}

variable "deploy_openshift_virtualization" {
  type    = bool
  default = false
}

variable "deploy_web_terminal" {
  type    = bool
  default = false
}

variable "deploy_advance_cluster_management" {
  type    = bool
  default = false
}

variable "agentic_model_api_base" {
  type    = string
  default = "http://qwen-25-7b-predictor.models.svc.cluster.local:8080/v1"
}

variable "agentic_model_id" {
  type    = string
  default = "qwen-25-7b"
}

variable "gitops_repo_url" {
  type    = string
  default = "https://github.com/sureshgaikwad/gitops-catalog"
}

variable "application_repo_path" {
  type    = string
  default = "application/vote-application"
}

variable "gitops_catalog_path" {
  type        = string
  default     = "../../gitops-catalog"
  description = "Path to gitops-catalog repo (clone alongside this repository or override)"
}

variable "assets_path" {
  type    = string
  default = "../../assets"
}
