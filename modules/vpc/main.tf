################################################################################
# VPC Module (handles both standard and zero-egress configurations)
#
# Standard (zero_egress = false):
#   Public + private subnets, Internet Gateway, NAT Gateways, S3 endpoint
#
# Zero Egress (zero_egress = true):
#   Private subnets only, no IGW/NAT, configurable VPC endpoints for AWS services
################################################################################

locals {
  tags               = var.tags == null ? {} : var.tags
  availability_zones = var.availability_zones != null ? var.availability_zones : slice(data.aws_availability_zones.available.names, 0, var.availability_zones_count)

  # Zero-egress endpoint configuration
  endpoint_config = {
    # Gateway endpoints (free, always recommended)
    gateway = {
      s3       = true
      dynamodb = var.enable_dynamodb_endpoint
    }
    # Interface endpoints by category
    interface = merge(
      # Required for ROSA HCP
      {
        ec2                  = true
        elasticloadbalancing = true
        sts                  = true
        "ecr.api"            = true
        "ecr.dkr"            = true
      },
      # EKS endpoints (required for ROSA HCP)
      var.enable_eks_endpoints ? {
        eks        = true
        "eks-auth" = true
      } : {},
      # Recommended endpoints
      var.enable_recommended_endpoints ? {
        logs           = true
        secretsmanager = true
        ssm            = true
        ssmmessages    = true
        ec2messages    = true
        kms            = true
      } : {},
      # User-specified additional endpoints
      { for ep in var.additional_endpoints : ep => true }
    )
  }

  gateway_endpoints   = { for k, v in local.endpoint_config.gateway : k => v if v }
  interface_endpoints = { for k, v in local.endpoint_config.interface : k => v if v }
}

################################################################################
# VPC
################################################################################

resource "aws_vpc" "vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = merge(
    { "Name" = "${var.name_prefix}-vpc" },
    local.tags,
  )
  lifecycle {
    ignore_changes = [tags]
  }
}

################################################################################
# Subnets
################################################################################

# Public subnets (standard VPC only -- zero-egress has no public subnets)
resource "aws_subnet" "public_subnet" {
  count = var.zero_egress ? 0 : length(local.availability_zones)

  vpc_id            = aws_vpc.vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, length(local.availability_zones) * 2, count.index)
  availability_zone = local.availability_zones[count.index]
  tags = merge(
    {
      "Name"                   = join("-", [var.name_prefix, "subnet", "public${count.index + 1}", local.availability_zones[count.index]])
      "kubernetes.io/role/elb" = ""
    },
    local.tags,
  )
  lifecycle {
    ignore_changes = [tags]
  }
}

# Private subnets (both standard and zero-egress, different CIDR calculation)
resource "aws_subnet" "private_subnet" {
  count = length(local.availability_zones)

  vpc_id = aws_vpc.vpc.id
  # Standard: public takes first N CIDR slots, private takes the next N
  # Zero-egress: only private subnets, starting from slot 0 with configurable subnet_bits
  cidr_block              = var.zero_egress ? cidrsubnet(var.vpc_cidr, var.subnet_bits, count.index) : cidrsubnet(var.vpc_cidr, length(local.availability_zones) * 2, count.index + length(local.availability_zones))
  availability_zone       = local.availability_zones[count.index]
  map_public_ip_on_launch = false
  tags = merge(
    {
      "Name"                            = var.zero_egress ? "${var.name_prefix}-private-${local.availability_zones[count.index]}" : join("-", [var.name_prefix, "subnet", "private${count.index + 1}", local.availability_zones[count.index]])
      "kubernetes.io/role/internal-elb" = var.zero_egress ? "1" : ""
    },
    local.tags,
  )
  lifecycle {
    ignore_changes = [tags]
  }
}

################################################################################
# Internet Gateway (standard VPC only)
################################################################################

resource "aws_internet_gateway" "internet_gateway" {
  count = var.zero_egress ? 0 : 1

  vpc_id = aws_vpc.vpc.id
  tags = merge(
    { "Name" = "${var.name_prefix}-igw" },
    local.tags,
  )
  lifecycle {
    ignore_changes = [tags]
  }
}

################################################################################
# Elastic IPs for NAT Gateways (standard VPC only)
################################################################################

resource "aws_eip" "eip" {
  count = var.zero_egress ? 0 : length(local.availability_zones)

  domain = "vpc"
  tags = merge(
    { "Name" = join("-", [var.name_prefix, "eip", local.availability_zones[count.index]]) },
    local.tags,
  )
  lifecycle {
    ignore_changes = [tags]
  }
}

################################################################################
# NAT Gateways (standard VPC only)
################################################################################

resource "aws_nat_gateway" "public_nat_gateway" {
  count = var.zero_egress ? 0 : length(local.availability_zones)

  allocation_id = aws_eip.eip[count.index].id
  subnet_id     = aws_subnet.public_subnet[count.index].id
  tags = merge(
    { "Name" = join("-", [var.name_prefix, "nat", "public${count.index}", local.availability_zones[count.index]]) },
    local.tags,
  )
  lifecycle {
    ignore_changes = [tags]
  }
}

################################################################################
# Route Tables
################################################################################

resource "aws_route_table" "public_route_table" {
  count = var.zero_egress ? 0 : 1

  vpc_id = aws_vpc.vpc.id
  tags = merge(
    { "Name" = "${var.name_prefix}-public" },
    local.tags,
  )
  lifecycle {
    ignore_changes = [tags]
  }
}

resource "aws_route_table" "private_route_table" {
  count = length(local.availability_zones)

  vpc_id = aws_vpc.vpc.id
  tags = merge(
    {
      "Name" = join("-", [var.name_prefix, "rtb", "private${count.index}", local.availability_zones[count.index]])
    },
    local.tags,
  )
  lifecycle {
    ignore_changes = [tags]
  }
}

################################################################################
# Routes (standard VPC only)
################################################################################

# Send all IPv4 traffic to the internet gateway
resource "aws_route" "ipv4_egress_route" {
  count = var.zero_egress ? 0 : 1

  route_table_id         = aws_route_table.public_route_table[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.internet_gateway[0].id
  depends_on             = [aws_route_table.public_route_table]
}

# Send all IPv6 traffic to the internet gateway
resource "aws_route" "ipv6_egress_route" {
  count = var.zero_egress ? 0 : 1

  route_table_id              = aws_route_table.public_route_table[0].id
  destination_ipv6_cidr_block = "::/0"
  gateway_id                  = aws_internet_gateway.internet_gateway[0].id
  depends_on                  = [aws_route_table.public_route_table]
}

# Send private traffic to NAT
resource "aws_route" "private_nat" {
  count = var.zero_egress ? 0 : length(local.availability_zones)

  route_table_id         = aws_route_table.private_route_table[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.public_nat_gateway[count.index].id
  depends_on             = [aws_route_table.private_route_table, aws_nat_gateway.public_nat_gateway]
}

################################################################################
# S3 Gateway Endpoint + Route Associations (standard VPC only)
# For zero-egress, gateway endpoints are managed in the section below.
################################################################################

resource "aws_vpc_endpoint" "s3" {
  count = var.zero_egress ? 0 : 1

  vpc_id       = aws_vpc.vpc.id
  service_name = "com.amazonaws.${data.aws_region.current.name}.s3"
}

resource "aws_vpc_endpoint_route_table_association" "private_vpc_endpoint_route_table_association" {
  count = var.zero_egress ? 0 : length(local.availability_zones)

  route_table_id  = aws_route_table.private_route_table[count.index].id
  vpc_endpoint_id = aws_vpc_endpoint.s3[0].id
}

################################################################################
# Route Table Associations
################################################################################

resource "aws_route_table_association" "public_route_table_association" {
  count = var.zero_egress ? 0 : length(local.availability_zones)

  subnet_id      = aws_subnet.public_subnet[count.index].id
  route_table_id = aws_route_table.public_route_table[0].id
}

resource "aws_route_table_association" "private_route_table_association" {
  count = length(local.availability_zones)

  subnet_id      = aws_subnet.private_subnet[count.index].id
  route_table_id = aws_route_table.private_route_table[count.index].id
}

################################################################################
# VPC Resource Wait (standard VPC only -- ensures all resources are ready)
################################################################################

resource "time_sleep" "vpc_resources_wait" {
  count = var.zero_egress ? 0 : 1

  create_duration  = "20s"
  destroy_duration = "20s"
  triggers = {
    vpc_id                                           = aws_vpc.vpc.id
    cidr_block                                       = aws_vpc.vpc.cidr_block
    ipv4_egress_route_id                             = aws_route.ipv4_egress_route[0].id
    ipv6_egress_route_id                             = aws_route.ipv6_egress_route[0].id
    private_nat_ids                                  = jsonencode([for value in aws_route.private_nat : value.id])
    private_vpc_endpoint_route_table_association_ids = jsonencode([for value in aws_vpc_endpoint_route_table_association.private_vpc_endpoint_route_table_association : value.id])
    public_route_table_association_ids               = jsonencode([for value in aws_route_table_association.public_route_table_association : value.id])
    private_route_table_association_ids              = jsonencode([for value in aws_route_table_association.private_route_table_association : value.id])
  }
}

################################################################################
# Zero-Egress: VPC Endpoint Security Group
################################################################################

resource "aws_security_group" "vpce" {
  count = var.zero_egress && var.create_endpoints && length(local.interface_endpoints) > 0 ? 1 : 0

  name_prefix = "${var.name_prefix}-vpce-"
  description = "Security group for VPC Endpoints"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = merge(local.tags, {
    Name = "${var.name_prefix}-vpce-sg"
  })

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [tags]
  }
}

################################################################################
# Zero-Egress: Gateway Endpoints (S3, DynamoDB)
################################################################################

resource "aws_vpc_endpoint" "gateway" {
  for_each = var.zero_egress && var.create_endpoints ? local.gateway_endpoints : {}

  vpc_id            = aws_vpc.vpc.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.${each.key}"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.private_route_table[*].id

  tags = merge(local.tags, {
    Name = "${var.name_prefix}-${each.key}-endpoint"
  })
}

################################################################################
# Zero-Egress: Interface Endpoints
################################################################################

resource "aws_vpc_endpoint" "interface" {
  for_each = var.zero_egress && var.create_endpoints ? local.interface_endpoints : {}

  vpc_id              = aws_vpc.vpc.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private_subnet[*].id
  security_group_ids  = [aws_security_group.vpce[0].id]
  private_dns_enabled = true

  tags = merge(local.tags, {
    Name = "${var.name_prefix}-${replace(each.key, ".", "-")}-endpoint"
  })
}

################################################################################
# Data Sources
################################################################################

data "aws_region" "current" {}

data "aws_availability_zones" "available" {
  state = "available"

  # Exclude Local Zones
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}
