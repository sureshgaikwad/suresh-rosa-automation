################################################################################
# Primary Outputs
################################################################################

output "vpc_id" {
  value       = var.zero_egress ? aws_vpc.vpc.id : time_sleep.vpc_resources_wait[0].triggers["vpc_id"]
  description = "The unique ID of the VPC"
}

output "cidr_block" {
  value       = var.zero_egress ? aws_vpc.vpc.cidr_block : time_sleep.vpc_resources_wait[0].triggers["cidr_block"]
  description = "The CIDR block of the VPC"
}

output "private_subnets" {
  value       = sort(aws_subnet.private_subnet[*].id)
  description = "List of private subnet IDs"
}

output "private_subnets_by_az" {
  value = {
    for idx, az in local.availability_zones : az => aws_subnet.private_subnet[idx].id
  }
  description = "Map of private subnet IDs keyed by availability zone"
}

output "public_subnets" {
  value       = var.zero_egress ? [] : sort(aws_subnet.public_subnet[*].id)
  description = "List of public subnet IDs (empty for zero-egress)"
}

output "availability_zones" {
  value       = aws_subnet.private_subnet[*].availability_zone
  description = "List of availability zones used"
}

################################################################################
# Additional Outputs
################################################################################

output "private_subnet_cidrs" {
  value       = aws_subnet.private_subnet[*].cidr_block
  description = "Private subnet CIDRs"
}

output "private_route_table_ids" {
  value       = aws_route_table.private_route_table[*].id
  description = "Private route table IDs"
}

################################################################################
# Zero-Egress Endpoint Outputs
################################################################################

output "vpce_security_group_id" {
  value       = var.zero_egress && var.create_endpoints && length(local.interface_endpoints) > 0 ? aws_security_group.vpce[0].id : null
  description = "VPC endpoint security group ID (zero-egress only)"
}

output "gateway_endpoint_ids" {
  value       = { for k, v in aws_vpc_endpoint.gateway : k => v.id }
  description = "Gateway endpoint IDs (zero-egress only)"
}

output "interface_endpoint_ids" {
  value       = { for k, v in aws_vpc_endpoint.interface : k => v.id }
  description = "Interface endpoint IDs (zero-egress only)"
}
