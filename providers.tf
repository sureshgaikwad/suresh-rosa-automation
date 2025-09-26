##############################################################
# Terraform and Provider Configuration
##############################################################

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.38"
    }
    rhcs = {
      source  = "terraform-redhat/rhcs"
      version = "~> 1.6"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

##############################################################
# Provider Configurations
##############################################################

# Configure AWS Provider
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(var.tags, {
      ManagedBy = "Terraform"
      Project   = "ROSA-Cluster"
    })
  }
}

# Configure RHCS Provider with authentication
provider "rhcs" {
  # Authentication can be provided via variables or environment variables
  # Priority: token > client_id/secret > environment variables
  token         = var.rhcs_token
  client_id     = var.rhcs_client_id
  client_secret = var.rhcs_client_secret
  url           = var.rhcs_url
}

# Configure Random Provider
provider "random" {}