##############################################################
# Core Cluster Configuration Variables
##############################################################

variable "cluster_name" {
  type        = string
  description = "Name of the cluster. After the creation of the resource, it is not possible to update the attribute value."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,14}[a-z0-9]$", var.cluster_name))
    error_message = "Cluster name must be 2-15 characters, start with letter, contain only lowercase letters, numbers, and hyphens."
  }
}

variable "openshift_version" {
  type        = string
  description = "Desired version of OpenShift for the cluster, for example '4.1.0'. If version is greater than the currently running version, an upgrade will be scheduled."

  validation {
    condition     = can(regex("^4\\.[0-9]+\\.[0-9]+$", var.openshift_version))
    error_message = "OpenShift version must be in format 4.x.y"
  }
}

variable "version_channel_group" {
  type        = string
  default     = "stable"
  description = "Desired channel group of the version [stable, candidate, fast, nightly]."

  validation {
    condition     = contains(["stable", "candidate", "fast", "nightly"], var.version_channel_group)
    error_message = "Version channel group must be one of: stable, candidate, fast, nightly."
  }
}

variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region for deploying resources"
}

variable "aws_account_id" {
  type        = string
  default     = null
  description = "AWS Account ID where resources will be deployed. If not provided, will be auto-detected from current credentials."
}

variable "aws_billing_account_id" {
  type        = string
  default     = null
  description = "The AWS billing account identifier where all resources are billed. If no information is provided, the data will be retrieved from the currently connected account."
}

variable "private" {
  type        = bool
  default     = false
  nullable    = false
  description = "Restrict master API endpoint and application routes to direct, private connectivity. (default: false)"
}

variable "private_cluster" {
  type        = bool
  default     = false
  description = "Create a private cluster. Alias for the 'private' variable."
}

##############################################################
# Admin User Configuration
##############################################################

variable "create_admin_user" {
  type        = bool
  default     = null
  description = "To create cluster admin user with default username `cluster-admin` and generated password. It will be ignored if `admin_credentials_username` or `admin_credentials_password` is set. (default: false)"
}

variable "admin_credentials_username" {
  type        = string
  default     = null
  description = "Admin username that is created with the cluster. auto generated username - \"cluster-admin\""
}

variable "admin_credentials_password" {
  type        = string
  default     = null
  description = "Admin password that is created with the cluster. The password must contain at least 14 characters (ASCII-standard) without whitespaces including uppercase letters, lowercase letters, and numbers or symbols."
  sensitive   = true
}

variable "admin_username" {
  type        = string
  default     = "cluster-admin"
  description = "Username for the admin user. Alias for admin_credentials_username."
}

##############################################################
# DNS Configuration
##############################################################

variable "create_dns_domain_reservation" {
  description = "Creates reserves a dns domain domain for the cluster. This value will be created by the install step if not pre created via this configuration."
  type        = bool
  default     = false
}

variable "base_dns_domain" {
  type        = string
  default     = null
  description = "Base DNS domain name previously reserved, e.g. '1vo8.p3.openshiftapps.com'."
}

##############################################################
# Cluster Properties and Tags
##############################################################

variable "properties" {
  description = "User defined properties."
  type        = map(string)
  default     = null
}

variable "tags" {
  description = "Apply user defined tags to all cluster resources created in AWS. After the creation of the cluster is completed, it is not possible to update this attribute."
  type        = map(string)
  default     = null
}

##############################################################
# Cluster Installation and Lifecycle Flags
##############################################################

variable "wait_for_create_complete" {
  type        = bool
  default     = true
  description = "Wait until the cluster is either in a ready state or in an error state. The waiter has a timeout of 20 minutes. (default: true)"
}

variable "wait_for_std_compute_nodes_complete" {
  type        = bool
  default     = true
  description = "Wait until the initial set of machine pools to be available. The waiter has a timeout of 60 minutes. (default: true)"
}

variable "disable_waiting_in_destroy" {
  type        = bool
  default     = null
  description = "Disable addressing cluster state in the destroy resource. Default value is false, and so a `destroy` will wait for the cluster to be deleted."
}

variable "destroy_timeout" {
  type        = number
  default     = null
  description = "Maximum duration in minutes to allow for destroying resources. (Default: 60 minutes)"
}

variable "upgrade_acknowledgements_for" {
  type        = string
  default     = null
  description = "Indicates acknowledgement of agreements required to upgrade the cluster version between minor versions (e.g. a value of \"4.12\" indicates acknowledgement of any agreements required to upgrade to OpenShift 4.12.z from 4.11 or before)."
}

variable "ec2_metadata_http_tokens" {
  type        = string
  default     = "optional"
  description = "Should cluster nodes use both v1 and v2 endpoints or just v2 endpoint of EC2 Instance Metadata Service (IMDS). Available since OpenShift 4.11.0."

  validation {
    condition     = contains(["required", "optional"], var.ec2_metadata_http_tokens)
    error_message = "EC2 metadata HTTP tokens must be either 'required' or 'optional'."
  }
}

variable "aws_additional_allowed_principals" {
  type        = list(string)
  default     = null
  description = "The additional allowed principals to use when installing the cluster."
}##############################################################
# Network and Connectivity Configuration Variables
##############################################################

variable "machine_cidr" {
  type        = string
  default     = null
  description = "Block of IP addresses used by OpenShift while installing the cluster, for example \"10.0.0.0/16\"."
}

variable "service_cidr" {
  type        = string
  default     = null
  description = "Block of IP addresses for services, for example \"172.30.0.0/16\"."
}

variable "pod_cidr" {
  type        = string
  default     = null
  description = "Block of IP addresses from which Pod IP addresses are allocated, for example \"10.128.0.0/14\"."
}

variable "host_prefix" {
  type        = number
  default     = null
  description = "Subnet prefix length to assign to each individual node. For example, if host prefix is set to \"23\", then each node is assigned a /23 subnet out of the given CIDR."
}

##############################################################
# VPC Configuration
##############################################################

variable "create_vpc" {
  type        = bool
  default     = true
  description = "Create a new VPC for the cluster. If false, existing vpc_cidr and aws_subnet_ids must be provided"
}

variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC. Only used when create_vpc is true"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "availability_zones" {
  type        = list(string)
  default     = null
  description = "List of availability zones for VPC creation. If null, uses first 3 AZs in the region"
}

variable "availability_zones_count" {
  type        = number
  default     = 3
  description = "Number of availability zones to use for VPC creation"

  validation {
    condition     = var.availability_zones_count >= 1 && var.availability_zones_count <= 6
    error_message = "Availability zones count must be between 1 and 6."
  }
}

variable "aws_subnet_ids" {
  type        = list(string)
  default     = null
  description = "The Subnet IDs to use when installing the cluster. Required when create_vpc is false."
}

variable "aws_availability_zones" {
  type        = list(string)
  default     = []
  description = "The AWS availability zones where instances of the default worker machine pool are deployed. Leave empty for the installer to pick availability zones"
}

##############################################################
# Proxy Configuration
##############################################################

variable "enable_proxy" {
  type        = bool
  default     = false
  description = "Enable proxy configuration for the cluster"
}

variable "http_proxy" {
  type        = string
  default     = null
  description = "A proxy URL to use for creating HTTP connections outside the cluster. The URL scheme must be http."
}

variable "https_proxy" {
  type        = string
  default     = null
  description = "A proxy URL to use for creating HTTPS connections outside the cluster."
}

variable "no_proxy" {
  type        = string
  default     = null
  description = "A comma-separated list of destination domain names, domains, IP addresses or other network CIDRs to exclude proxying."
}

variable "additional_trust_bundle" {
  type        = string
  default     = null
  description = "A string containing a PEM-encoded X.509 certificate bundle that will be added to the nodes' trusted certificate store."
}

##############################################################
# Default Ingress Configuration
##############################################################

variable "default_ingress_listening_method" {
  type        = string
  default     = ""
  description = "Listening Method for ingress. Options are [\"internal\", \"external\"]. Default is \"external\". When empty is set based on private variable."

  validation {
    condition     = var.default_ingress_listening_method == "" || contains(["internal", "external"], var.default_ingress_listening_method)
    error_message = "Default ingress listening method must be either 'internal', 'external', or empty."
  }
}

##############################################################
# Bastion Host Configuration
##############################################################

variable "create_bastion_host" {
  type        = bool
  default     = false
  description = "Create a bastion host for accessing the private cluster"
}

variable "bastion_instance_type" {
  type        = string
  default     = "t3.micro"
  description = "Instance type for the bastion host"
}

variable "bastion_ssh_key_name" {
  type        = string
  default     = null
  description = "SSH key pair name for bastion host access"
}##############################################################
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
}##############################################################
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

variable "deploy_openshift_servicemesh" {
  type        = bool
  default     = false
  description = "Deploy OpenShift Service Mesh operator via ArgoCD application"
}

variable "deploy_nfd" {
  type        = bool
  default     = false
  description = "Deploy NodeFileDiscovery operator via ArgoCD"
}

variable "deploy_nvidia_gpu_operator" {
  type        = bool
  default     = false
  description = "Deploy NVIDIA GPU operator via ArgoCD"
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

variable "deploy_gpu_operator" {
  type    = bool
  default = true
}

variable "deploy_keycloak" {
  type        = bool
  default     = false
  description = "Deploy Keycloak operator and instance via ArgoCD using gitops-catalog repository"
}

variable "deploy_developerhub" {
  type        = bool
  default     = false
  description = "Deploy Red Hat Developer Hub operator and instance via ArgoCD using gitops-catalog repository"
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