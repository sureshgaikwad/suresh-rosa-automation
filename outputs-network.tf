##############################################################
# VPC and Network Outputs
##############################################################

output "vpc_id" {
  value       = var.create_vpc ? module.vpc[0].vpc_id : null
  description = "ID of the VPC created by the VPC module"
}

output "vpc_cidr" {
  value       = var.create_vpc ? module.vpc[0].cidr_block : null
  description = "CIDR block of the VPC created by the VPC module"
}

output "private_subnets" {
  value       = var.create_vpc ? module.vpc[0].private_subnets : var.aws_subnet_ids
  description = "List of private subnet IDs used by the cluster"
}

output "cluster_subnets" {
  value       = local.cluster_subnet_ids
  description = "List of all subnet IDs (public + private) used by the cluster"
}

output "public_subnets" {
  value       = var.create_vpc ? module.vpc[0].public_subnets : null
  description = "List of public subnet IDs created by the VPC module (only available when create_vpc is true)"
}

output "availability_zones" {
  value       = var.create_vpc ? module.vpc[0].availability_zones : var.aws_availability_zones
  description = "List of availability zones used by the VPC/cluster"
}