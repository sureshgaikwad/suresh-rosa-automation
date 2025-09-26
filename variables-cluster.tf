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
}