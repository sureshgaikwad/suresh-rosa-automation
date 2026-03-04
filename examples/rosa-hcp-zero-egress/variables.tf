################################################################################
# ROSA HCP Zero Egress Example Variables
################################################################################

################################################################################
# Required Variables
################################################################################

variable "cluster_name" {
  type        = string
  description = "Name of the ROSA cluster (2-15 chars, lowercase, alphanumeric and hyphens)"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,13}[a-z0-9]$", var.cluster_name))
    error_message = "Cluster name must be 2-15 characters, start with letter, lowercase alphanumeric and hyphens only."
  }
}

variable "openshift_version" {
  type        = string
  description = "OpenShift version (e.g., '4.15.0')"
  default     = "4.15.0"
}

variable "aws_region" {
  type        = string
  description = "AWS region"
  default     = "us-east-1"
}

################################################################################
# VPC Configuration - Choose Option A or B
################################################################################

variable "create_vpc" {
  type        = bool
  default     = true
  description = "Create new zero egress VPC (true) or use existing VPC (false)"
}

# Option A: Create new VPC (used when create_vpc = true)
variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for new VPC (when create_vpc = true)"
}

variable "availability_zones_count" {
  type        = number
  default     = 3
  description = "Number of AZs for new VPC (when create_vpc = true)"
}

variable "enable_dynamodb_endpoint" {
  type        = bool
  default     = false
  description = "Enable DynamoDB endpoint (when create_vpc = true)"
}

# Option B: Use existing VPC (used when create_vpc = false)
variable "existing_subnet_ids" {
  type        = list(string)
  default     = null
  description = "Existing private subnet IDs (when create_vpc = false). Must be private subnets."
}

variable "existing_vpc_cidr" {
  type        = string
  default     = null
  description = "Existing VPC CIDR (when create_vpc = false)"
}

################################################################################
# Compute Configuration
################################################################################

variable "replicas" {
  type        = number
  default     = 2
  description = "Number of worker nodes"
}

variable "compute_machine_type" {
  type        = string
  default     = "m5.xlarge"
  description = "EC2 instance type for workers"
}

################################################################################
# Admin User Configuration
################################################################################

variable "create_admin_user" {
  type        = bool
  default     = true
  description = "Create cluster admin user"
}

################################################################################
# IAM Configuration
################################################################################

variable "path" {
  type        = string
  default     = "/"
  description = "IAM path for roles"
}

################################################################################
# Tags
################################################################################

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags for all resources"
}
