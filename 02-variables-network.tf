##############################################################
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
  description = "The Subnet IDs to use when installing the cluster. For private ROSA HCP clusters, provide private subnets only. For public clusters, provide both public and private subnets. Required when create_vpc is false."
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
# Shared VPC Configuration
##############################################################

variable "shared_vpc" {
  type = object({
    ingress_private_hosted_zone_id                = string
    internal_communication_private_hosted_zone_id = string
    route53_role_arn                              = string
    vpce_role_arn                                 = string
  })
  default     = null
  description = "Shared VPC settings for deploying ROSA into a VPC owned by a different AWS account."
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
}

##############################################################
# Zero Egress Configuration
##############################################################

variable "zero_egress" {
  type        = bool
  default     = false
  description = "Deploy a zero egress ROSA cluster. When true, creates a VPC with no internet egress and configures the cluster for private operation with VPC endpoints."
}

variable "zero_egress_vpc_endpoints" {
  type        = bool
  default     = true
  description = "Create VPC endpoints for AWS services when deploying a zero egress cluster. Required for zero egress operation."
}

variable "zero_egress_additional_endpoints" {
  type        = list(string)
  default     = []
  description = "Additional VPC interface endpoints to create for zero egress cluster (e.g., ['sqs', 'sns'])"
}
