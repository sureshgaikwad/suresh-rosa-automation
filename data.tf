##############################################################
# Data Sources
##############################################################

# Get current AWS account information
data "aws_caller_identity" "current" {}

# Data source for existing subnets (when not creating VPC)
data "aws_subnet" "provided_subnet" {
  count = var.create_vpc ? 0 : length(var.aws_subnet_ids != null ? var.aws_subnet_ids : [])
  id    = var.aws_subnet_ids[count.index]
}