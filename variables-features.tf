##############################################################
# Machine Pool and Compute Configuration
##############################################################

variable "replicas" {
  type        = number
  default     = null
  description = "Number of worker nodes to provision. This attribute is applicable solely when autoscaling is disabled. Single zone clusters need at least 2 nodes, multizone clusters need at least 3 nodes. Hosted clusters require that the number of worker nodes be a multiple of the number of private subnets. (default: 2)"
}

variable "compute_machine_type" {
  type        = string
  default     = null
  description = "Identifies the Instance type used by the default worker machine pool e.g. `m5.xlarge`. Use the `rhcs_machine_types` data source to find the possible values."
}

variable "aws_additional_compute_security_group_ids" {
  type        = list(string)
  default     = null
  description = "The additional security group IDs to be added to the default worker machine pool."
}

##############################################################
# Additional Machine Pools Configuration
##############################################################

variable "create_additional_machine_pools" {
  type        = bool
  default     = false
  description = "Create additional machine pools beyond the default one"
}

variable "machine_pools" {
  type        = map(any)
  default     = {}
  description = "Provides a generic approach to add multiple machine pools after the creation of the cluster. This variable allows users to specify configurations for multiple machine pools in a flexible and customizable manner, facilitating the management of resources post-cluster deployment. For additional details regarding the variables utilized, refer to the [machine-pool sub-module](./modules/machine-pool). For non-primitive variables (such as maps, lists, and objects), supply the JSON-encoded string."
}

variable "ignore_machine_pools_deletion_error" {
  type        = bool
  default     = false
  description = "Ignore machine pool deletion error. Assists when cluster resource is managed within the same file for the destroy use case"
}

##############################################################
# Autoscaling Configuration
##############################################################

variable "cluster_autoscaler_enabled" {
  type        = bool
  default     = false
  description = "Enable Autoscaler for this cluster. This resource is currently unavailable and using will result in error 'Autoscaler configuration is not available'"
}

variable "enable_autoscaling" {
  type        = bool
  default     = false
  description = "Enable autoscaling for the default machine pool"
}

variable "autoscaling_min_replicas" {
  type        = number
  default     = 2
  description = "Minimum number of replicas for autoscaling"
}

variable "autoscaling_max_replicas" {
  type        = number
  default     = 10
  description = "Maximum number of replicas for autoscaling"
}

variable "autoscaler_max_pod_grace_period" {
  type        = number
  default     = null
  description = "Gives pods graceful termination time before scaling down."
}

variable "autoscaler_pod_priority_threshold" {
  type        = number
  default     = null
  description = "To allow users to schedule 'best-effort' pods, which shouldn't trigger Cluster Autoscaler actions, but only run when there are spare resources available."
}

variable "autoscaler_max_node_provision_time" {
  type        = string
  default     = null
  description = "Maximum time cluster-autoscaler waits for node to be provisioned."
}

variable "autoscaler_max_nodes_total" {
  type        = number
  default     = null
  description = "Maximum number of nodes in all node groups. Cluster autoscaler will not grow the cluster beyond this number."
}

##############################################################
# Kubelet Configuration
##############################################################

variable "kubelet_configs" {
  type        = map(any)
  default     = {}
  description = "Provides a generic approach to add multiple kubelet configs after the creation of the cluster. This variable allows users to specify configurations for multiple kubelet configs in a flexible and customizable manner, facilitating the management of resources post-cluster deployment. For additional details regarding the variables utilized, refer to the [idp sub-module](./modules/kubelet-configs). For non-primitive variables (such as maps, lists, and objects), supply the JSON-encoded string."
}

##############################################################
# Encryption Configuration
##############################################################

variable "enable_etcd_encryption" {
  type        = bool
  default     = false
  description = "Enable etcd encryption for the cluster"
}

variable "enable_ebs_encryption" {
  type        = bool
  default     = false
  description = "Enable EBS encryption for the cluster"
}

variable "etcd_encryption" {
  type        = bool
  default     = null
  description = "Add etcd encryption. By default etcd data is encrypted at rest. This option configures etcd encryption on top of existing storage encryption."
}

variable "kms_key_arn" {
  type        = string
  default     = null
  description = "The key ARN is the Amazon Resource Name (ARN) of a CMK. It is a unique, fully qualified identifier for the CMK. A key ARN includes the AWS account, Region, and the key ID."
}

variable "etcd_kms_key_arn" {
  type        = string
  default     = null
  description = "The key ARN is the Amazon Resource Name (ARN) of a CMK. It is a unique, fully qualified identifier for the CMK. A key ARN includes the AWS account, Region, and the key ID."
}

##############################################################
# OpenShift Features and Operators
##############################################################

variable "deploy_openshift_gitops" {
  type        = bool
  default     = true
  description = "Deploy OpenShift GitOps operator"
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