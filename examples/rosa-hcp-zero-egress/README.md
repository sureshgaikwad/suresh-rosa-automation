# ROSA HCP Zero Egress Cluster Example

Deploy a ROSA HCP cluster with zero egress networking - no internet access from cluster nodes.

## Design Philosophy

This example follows **Terraform best practices**:

1. **Flexible VPC Options** - Create new VPC or use existing
2. **Loosely Coupled Modules** - Easy to replace when upstream adds support
3. **Optional Image Mirroring** - Configured separately if needed
4. **Minimal Configuration** - Sensible defaults, fewer required inputs

## Quick Start

### Option A: Create New Zero Egress VPC

```hcl
# terraform.tfvars
cluster_name      = "my-cluster"
openshift_version = "4.15.0"
create_vpc        = true
vpc_cidr          = "10.0.0.0/16"
```

### Option B: Use Existing VPC and Subnets

```hcl
# terraform.tfvars
cluster_name         = "my-cluster"
openshift_version    = "4.15.0"
create_vpc           = false
existing_subnet_ids  = ["subnet-abc123", "subnet-def456", "subnet-ghi789"]
existing_vpc_cidr    = "10.0.0.0/16"
```

## Usage

```bash
# Set RHCS token
export RHCS_TOKEN="your-ocm-token"

# Deploy
terraform init
terraform plan
terraform apply
```

## Optional: Configure Image Mirrors

If your environment requires image mirroring (disconnected/air-gapped), uncomment the image mirror modules in `main.tf`:

```hcl
module "image_mirror_redhat" {
  source = "../../modules/image-mirrors"

  cluster_id      = module.rosa_cluster.cluster_id
  type            = "digest"
  source_registry = "registry.redhat.io"
  mirrors         = ["123456789012.dkr.ecr.us-east-1.amazonaws.com/redhat-io"]
}
```

## Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| cluster_name | Cluster name | `string` | n/a | yes |
| openshift_version | OpenShift version | `string` | `"4.15.0"` | no |
| create_vpc | Create new VPC or use existing | `bool` | `true` | no |
| vpc_cidr | New VPC CIDR (if create_vpc=true) | `string` | `"10.0.0.0/16"` | no |
| existing_subnet_ids | Existing subnet IDs (if create_vpc=false) | `list(string)` | `null` | no |
| existing_vpc_cidr | Existing VPC CIDR (if create_vpc=false) | `string` | `null` | no |
| replicas | Worker node count | `number` | `2` | no |
| compute_machine_type | EC2 instance type | `string` | `"m5.xlarge"` | no |

## Outputs

| Name | Description |
|------|-------------|
| cluster_id | Cluster ID |
| cluster_api_url | API server URL (private) |
| cluster_console_url | Web console URL (private) |
| vpc_id | VPC ID (if created) |
| private_subnet_ids | Subnet IDs used |

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Zero Egress VPC                              │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                       │
│  │ Private  │  │ Private  │  │ Private  │                       │
│  │ Subnet   │  │ Subnet   │  │ Subnet   │  ← No NAT Gateway     │
│  │  AZ-1    │  │  AZ-2    │  │  AZ-3    │  ← No Internet Egress │
│  └──────────┘  └──────────┘  └──────────┘                       │
│         │            │            │                              │
│         └────────────┼────────────┘                              │
│                      │                                           │
│  ┌───────────────────┴───────────────────┐                      │
│  │          VPC Endpoints                 │                      │
│  │  S3 | ECR | EC2 | ELB | STS | EKS     │                      │
│  └───────────────────────────────────────┘                      │
│                      │                                           │
│                      ▼ (PrivateLink)                            │
│              ROSA HCP Control Plane                              │
└─────────────────────────────────────────────────────────────────┘
```

## Migration to Upstream

When `terraform-rhcs-rosa-hcp` adds official zero egress support:

1. Replace `modules/rosa-cluster-hcp` with upstream module
2. Add any new zero-egress-specific parameters
3. Run `terraform plan` to verify no resource recreation

The modules are designed for easy transition.

## Prerequisites for Existing VPC

If using `create_vpc = false`, ensure your VPC has:

1. **Private subnets** in multiple AZs
2. **VPC Endpoints** for: S3, ECR, EC2, ELB, STS, EKS
3. **DNS resolution** enabled
4. **No NAT gateway** (zero egress)
