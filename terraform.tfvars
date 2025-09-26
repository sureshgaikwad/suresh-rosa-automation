# Example terraform.tfvars file
# Copy this file to terraform.tfvars and update the values

##############################################################
# Required Variables
##############################################################
cluster_name      = "sgaikwad-cluster"
openshift_version = "4.19.6"
aws_region        = "us-east-1"
rhcs_token        = "eyJhbGciOiJIUzUxMiIsInR5cCIgOiAiSldUIiwia2lkIiA6ICI0NzQzYTkzMC03YmJiLTRkZGQtOTgzMS00ODcxNGRlZDc0YjUifQ.eyJpYXQiOjE3NTU1MDE2OTYsImp0aSI6ImE4ZWJiZmI2LWE1OTctNDNkZi1hNzJmLTk3MmNjNzI2MDIyMiIsImlzcyI6Imh0dHBzOi8vc3NvLnJlZGhhdC5jb20vYXV0aC9yZWFsbXMvcmVkaGF0LWV4dGVybmFsIiwiYXVkIjoiaHR0cHM6Ly9zc28ucmVkaGF0LmNvbS9hdXRoL3JlYWxtcy9yZWRoYXQtZXh0ZXJuYWwiLCJzdWIiOiJmOjUyOGQ3NmZmLWY3MDgtNDNlZC04Y2Q1LWZlMTZmNGZlMGNlNjpyaG4tc3VwcG9ydC1zZ2Fpa3dhZCIsInR5cCI6Ik9mZmxpbmUiLCJhenAiOiJjbG91ZC1zZXJ2aWNlcyIsIm5vbmNlIjoiZDFmYWFhMjUtNmFhZi00ZWUxLWI4OWQtYmZkMTZmNTBkOTZkIiwic2lkIjoiNzE0NmY2YjItMGU0NS00MDM2LWEyNDEtNGMyZDY1MDJkZTUxIiwic2NvcGUiOiJvcGVuaWQgYmFzaWMgYXBpLmlhbS5zZXJ2aWNlX2FjY291bnRzIHJvbGVzIHdlYi1vcmlnaW5zIGNsaWVudF90eXBlLnByZV9rYzI1IG9mZmxpbmVfYWNjZXNzIn0.8sr9PvFrXYYxNF36FmomyhzDORW4FIjhfnVQq3MxB7qYDGgfYA__PZIBSszeuAR10PDXLcQXY90D7CQe73hO3g"

# AWS Account Configuration (optional - will auto-detect if not provided)
aws_account_id         = "808082629126" # AWS account where cluster will be deployed
aws_billing_account_id = "015719942846" # AWS account for billing (defaults to aws_account_id)

##############################################################
# VPC Configuration
##############################################################
create_vpc = true
vpc_cidr   = "10.0.0.0/16"

# If using existing VPC, set create_vpc = false and provide:
# aws_subnet_ids         = ["subnet-12345", "subnet-67890", "subnet-abcdef"]
# aws_availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
# machine_cidr          = "10.0.0.0/16"

##############################################################
# Admin User Configuration
##############################################################
admin_username = "cluster-admin"
# admin_password = "YourSecurePassword123!" # Optional, random password will be generated if not provided

##############################################################
# Cluster Configuration
##############################################################
private_cluster      = false
compute_machine_type = "m5.xlarge"
replicas             = 6
##############################################################
# Optional Network Configuration
##############################################################
# service_cidr = "172.30.0.0/16"
# pod_cidr     = "10.128.0.0/14"
# host_prefix  = 23

##############################################################
# Machine Pools Configuration
##############################################################
create_additional_machine_pools = true
enable_autoscaling              = true
autoscaling_min_replicas        = 6
autoscaling_max_replicas        = 10

# Example additional machine pools configuration:
machine_pools = {
  #   "worker-pool-1" = {
  #     name          = "worker-pool-1"
  #     instance_type = "m6a.xlarge"
  #     replicas      = 2
  #     subnet_id     = "subnet-12345"
  #     labels = {
  #       "node-type" = "compute"
  #     }
  #     # Optional autoscaling configuration
  #     autoscaling = {
  #       min_replicas = 2
  #       max_replicas = 5
  #     }
  #   }
  "gpu-pool" = {
    name          = "gpu-pool"
    instance_type = "g6.8xlarge"
    replicas      = 1
    labels = {
      "node-type" = "gpu"
      "workload"  = "ai"
    }
    taints = [
      {
        key           = "nvidia.com/gpu"
        value         = "true"
        schedule_type = "NoSchedule"
      }
    ]
  }
}

##############################################################
# Bastion Host Configuration
##############################################################
create_bastion_host   = false
bastion_instance_type = "t3.micro"
# bastion_ssh_key_name = "my-key-pair"  # Required if create_bastion_host = true

##############################################################
# Identity Providers Configuration
##############################################################
create_identity_providers = false

# Example identity providers configuration:
# identity_providers = {
#   "github-idp" = {
#     name     = "github-corp"
#     idp_type = "github"
#     github_idp_client_id     = "your-github-client-id"
#     github_idp_client_secret = "your-github-client-secret"
#     github_idp_organizations = ["your-github-org"]
#     mapping_method           = "claim"
#   }
#   "htpasswd-idp" = {
#     name     = "local-users"
#     idp_type = "htpasswd"
#     htpasswd_idp_users = [
#       {
#         username = "admin"
#         password = "secure-password"
#       },
#       {
#         username = "developer"
#         password = "another-password"
#       }
#     ]
#   }
# }

##############################################################
# Roles and OIDC Configuration
##############################################################
create_account_roles  = true
create_operator_roles = true
create_oidc           = true
managed_oidc          = true
create_ocm_role       = false
# ocm_role_name      = "ManagedOpenShift-OCM-Role"

##############################################################
# Encryption Configuration
##############################################################
enable_etcd_encryption = false
enable_ebs_encryption  = false
# etcd_kms_key_arn     = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
# kms_key_arn          = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"

##############################################################
# Proxy Configuration
##############################################################
enable_proxy = false
# http_proxy              = "http://proxy.company.com:8080"
# https_proxy             = "https://proxy.company.com:8080"
# no_proxy                = "localhost,127.0.0.1,.company.com"
# additional_trust_bundle = "-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----"

##############################################################
# Red Hat Cloud Services (RHCS) Authentication
##############################################################
# Option 1: Provide credentials via variables (not recommended for production)
# rhcs_client_id     = "your-actual-rhcs-client-id"
# rhcs_client_secret = "your-actual-rhcs-client-secret"

# Option 2: Use environment variables (recommended)
# export RHCS_CLIENT_ID = "bd2522cc-c056-4d19-bf8d-e799961821c9"
# export RHCS_CLIENT_SECRET = "jZt8ncvYhfcr4AU86SZeufen3eP2ygBx"
# Optional: Custom OCM URL (default is production)
# rhcs_url = "https://api.stage.openshift.com"  # For staging environment

##############################################################
# OpenShift GitOps Configuration
##############################################################
deploy_openshift_gitops = true
deploy_vote_application = true
gitops_repo_url         = "https://github.com/sureshgaikwad/gitops-catalog"
application_repo_path   = "application/vote-application"

##############################################################
# Operator Deployments   
##############################################################
deploy_openshift_ai                    = true
deploy_openshift_serverless            = true
deploy_openshift_servicemesh           = true
deploy_ai_model                        = true
deploy_nfd                             = true
deploy_nfd_application                 = true
deploy_nvidia_gpu_operator             = true
deploy_nvidia_gpu_operator_application = true
deploy_openshift_lightspeed            = true
deploy_authorino_operator               = true


##############################################################
# Tags
##############################################################
tags = {
  Environment = "development"
  Team        = "platform"
  Project     = "rosa-cluster"
}
