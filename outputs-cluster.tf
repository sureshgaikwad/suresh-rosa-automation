##############################################################
# Cluster Information Outputs
##############################################################

output "cluster_id" {
  value       = module.rosa_cluster_hcp.cluster_id
  description = "Unique identifier of the cluster."
}

output "cluster_admin_username" {
  value       = module.rosa_cluster_hcp.cluster_admin_username
  description = "The username of the admin user."
}

output "cluster_admin_password" {
  value       = module.rosa_cluster_hcp.cluster_admin_password
  description = "The password of the admin user."
  sensitive   = true
}

output "cluster_api_url" {
  value       = module.rosa_cluster_hcp.cluster_api_url
  description = "The URL of the API server."
}

output "cluster_console_url" {
  value       = module.rosa_cluster_hcp.cluster_console_url
  description = "The URL of the console."
}

output "cluster_domain" {
  value       = module.rosa_cluster_hcp.cluster_domain
  description = "The DNS domain of cluster."
}

output "cluster_current_version" {
  value       = module.rosa_cluster_hcp.cluster_current_version
  description = "The currently running version of OpenShift on the cluster, for example '4.11.0'."
}

output "cluster_state" {
  value       = module.rosa_cluster_hcp.cluster_state
  description = "The state of the cluster."
}

##############################################################
# Machine Pools Outputs
##############################################################

output "additional_machine_pools" {
  value = {
    for k, v in module.rhcs_hcp_machine_pool : k => {
      id        = v.machine_pool_id
      name      = v.machine_pool_name
      subnet_id = v.subnet_id
      replicas  = v.replicas
    }
  }
  description = "Map of additional machine pools created"
}