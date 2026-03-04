################################################################################
# Required
################################################################################

variable "name_prefix" {
  type        = string
  description = "User-defined prefix for all generated AWS resources of this VPC."

  validation {
    condition     = length(var.name_prefix) >= 1 && length(var.name_prefix) <= 32
    error_message = "Name prefix must be 1-32 characters."
  }
}

################################################################################
# VPC Configuration
################################################################################

variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC."

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "Must be a valid CIDR."
  }
}

variable "availability_zones" {
  type        = list(string)
  default     = null
  description = "Specific availability zones to use. If null, auto-selects based on count."
}

variable "availability_zones_count" {
  type        = number
  default     = 3
  description = "Number of AZs when availability_zones is null."

  validation {
    condition     = var.availability_zones_count >= 1 && var.availability_zones_count <= 6
    error_message = "Must be 1-6."
  }
}

variable "tags" {
  type        = map(string)
  default     = null
  description = "Tags for all resources."
}

################################################################################
# Zero Egress Configuration
################################################################################

variable "zero_egress" {
  type        = bool
  default     = false
  description = "When true, creates a zero-egress VPC: private subnets only, no IGW/NAT, with configurable VPC endpoints."
}

variable "subnet_bits" {
  type        = number
  default     = 4
  description = "Bits to extend VPC CIDR for private subnets in zero-egress mode (e.g., /16 + 4 = /20). Ignored for standard VPC."

  validation {
    condition     = var.subnet_bits >= 1 && var.subnet_bits <= 8
    error_message = "Must be 1-8."
  }
}

################################################################################
# VPC Endpoints Configuration (used when zero_egress = true)
################################################################################

variable "create_endpoints" {
  type        = bool
  default     = false
  description = "Create VPC endpoints. Required for zero-egress operation."
}

variable "enable_eks_endpoints" {
  type        = bool
  default     = true
  description = "Enable EKS endpoints (required for ROSA HCP)."
}

variable "enable_recommended_endpoints" {
  type        = bool
  default     = true
  description = "Enable recommended endpoints (logs, ssm, kms, etc.)."
}

variable "enable_dynamodb_endpoint" {
  type        = bool
  default     = false
  description = "Enable DynamoDB gateway endpoint."
}

variable "additional_endpoints" {
  type        = list(string)
  default     = []
  description = "Additional interface endpoints (e.g., ['sqs', 'sns'])."
}
