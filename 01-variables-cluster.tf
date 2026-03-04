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

variable "domain_prefix" {
  type        = string
  default     = null
  description = "Creates a domain_prefix for your ROSA cluster. Defaults to a random string if not set."
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
}

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
  type = map(object({
    name        = string
    replicas    = optional(number)
    auto_repair = optional(bool)

    # If autoscaling is set, replicas is ignored (matches current behavior in main.tf)
    autoscaling = optional(object({
      min_replicas = optional(number)
      max_replicas = optional(number)
    }))

    # Either provide aws_node_pool or the legacy instance_type/tags/additional_security_group_ids fields.
    aws_node_pool = optional(object({
      instance_type                 = optional(string)
      tags                          = optional(map(string))
      additional_security_group_ids = optional(list(string))
    }))

    instance_type                 = optional(string)
    tags                          = optional(map(string))
    additional_security_group_ids = optional(list(string))

    subnet_id = optional(string)

    tuning_configs               = optional(list(string))
    upgrade_acknowledgements_for = optional(string)
    kubelet_configs              = optional(string)

    labels = optional(map(string))
    taints = optional(list(object({
      key           = string
      value         = string
      schedule_type = string
    })))
  }))
  default     = {}
  description = "Map of additional machine pool configs (strongly typed)."
}

variable "ignore_machine_pools_deletion_error" {
  type        = bool
  default     = false
  description = "Ignore machine pool deletion error. Assists when cluster resource is managed within the same file for the destroy use case"
}

##############################################################
# Image Mirrors Configuration
##############################################################

variable "image_mirrors" {
  type        = map(any)
  default     = {}
  description = "Provides a generic approach to add multiple image mirrors after the creation of the cluster. This variable allows users to specify configurations for multiple image mirrors in a flexible and customizable manner, facilitating the management of resources post-cluster deployment. For additional details regarding the variables utilized, refer to the [image-mirrors sub-module](./modules/image-mirrors). For non-primitive variables (such as maps, lists, and objects), supply the JSON-encoded string."
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
  type = map(object({
    name           = string
    pod_pids_limit = optional(number)
  }))
  default     = {}
  description = "Map of kubelet config definitions (strongly typed)."
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
# Registry Configuration
##############################################################

variable "registry_config" {
  type = object({
    additional_trusted_ca = optional(map(string))
    allowed_registries_for_import = optional(
      list(
        object(
          {
            domain_name = optional(string)
            insecure    = optional(bool)
          }
        )
      )
    )
    platform_allowlist_id = optional(string)
    registry_sources = optional(
      object(
        {
          allowed_registries  = optional(list(string))
          blocked_registries  = optional(list(string))
          insecure_registries = optional(list(string))
        }
      )
    )
  })
  default     = null
  description = "Registry configuration for this cluster."

  validation {
    condition = var.registry_config == null ? true : (
      var.registry_config.registry_sources == null ? true : (
        !(
          can(var.registry_config.registry_sources.allowed_registries) &&
          length(coalesce(var.registry_config.registry_sources.allowed_registries, [])) > 0 &&
          can(var.registry_config.registry_sources.blocked_registries) &&
          length(coalesce(var.registry_config.registry_sources.blocked_registries, [])) > 0
        )
      )
    )
    error_message = "Registry config cannot specify both allowed_registries and blocked_registries - they are mutually exclusive."
  }
}
