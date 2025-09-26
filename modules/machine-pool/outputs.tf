output "machine_pool_id" {
  value       = rhcs_hcp_machine_pool.machine_pool.id
  description = "The ID of the machine pool"
}

output "machine_pool_name" {
  value       = rhcs_hcp_machine_pool.machine_pool.name
  description = "The name of the machine pool"
}

output "subnet_id" {
  value       = rhcs_hcp_machine_pool.machine_pool.subnet_id
  description = "The subnet ID where the machine pool is deployed"
}

output "replicas" {
  value       = rhcs_hcp_machine_pool.machine_pool.replicas
  description = "The number of replicas for the machine pool"
}

output "availability_zone" {
  value       = rhcs_hcp_machine_pool.machine_pool.availability_zone
  description = "The availability zone of the machine pool"
}

output "instance_type" {
  value       = rhcs_hcp_machine_pool.machine_pool.aws_node_pool.instance_type
  description = "The instance type of the machine pool"
}

output "autoscaling" {
  value       = rhcs_hcp_machine_pool.machine_pool.autoscaling
  description = "The autoscaling configuration of the machine pool"
}
