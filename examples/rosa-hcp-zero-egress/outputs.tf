################################################################################
# Outputs
################################################################################

output "cluster_id" {
  value       = module.cluster.cluster_id
  description = "Cluster ID"
}

output "cluster_api_url" {
  value       = module.cluster.cluster_api_url
  description = "API URL (private)"
}

output "cluster_console_url" {
  value       = module.cluster.cluster_console_url
  description = "Console URL (private)"
}

output "cluster_admin_username" {
  value       = module.cluster.cluster_admin_username
  description = "Admin username"
}

output "cluster_admin_password" {
  value       = module.cluster.cluster_admin_password
  description = "Admin password"
  sensitive   = true
}

output "vpc_id" {
  value       = var.create_vpc ? module.vpc[0].vpc_id : null
  description = "VPC ID (if created)"
}

output "subnet_ids" {
  value       = local.subnet_ids
  description = "Subnet IDs used"
}
