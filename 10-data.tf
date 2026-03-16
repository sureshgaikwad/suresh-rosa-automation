##############################################################
# Data Sources
##############################################################

# Get current AWS account information
data "aws_caller_identity" "current" {}

# Get current AWS partition (supports commercial + GovCloud)
data "aws_partition" "current" {}

# Data source for existing subnets (when not creating VPC)
data "aws_subnet" "provided_subnet" {
  count = var.create_vpc ? 0 : length(var.aws_subnet_ids != null ? var.aws_subnet_ids : [])
  id    = var.aws_subnet_ids[count.index]
}

# Instance type offerings used to choose machine pool subnet/AZ dynamically
data "aws_ec2_instance_type_offerings" "machine_pool_instance_azs" {
  for_each      = toset(local.additional_machine_pool_instance_types)
  location_type = "availability-zone"

  filter {
    name   = "instance-type"
    values = [each.value]
  }
}