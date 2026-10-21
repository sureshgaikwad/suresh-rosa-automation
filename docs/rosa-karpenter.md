# Red Hat build of Karpenter (AutoNode) on ROSA HCP

Karpenter controllers run in the **hosted control plane** (not as worker pods).
This repo splits responsibilities the same way as other features:

| Layer | What | How |
|-------|------|-----|
| **Cluster Terraform** | IAM role + enable AutoNode | `enable_karpenter = true` |
| **GitOps catalog** | `NodePool` CRs | `operators/rosa-karpenter` (**must be on `gitops_repo_url` before apply**) |
| **GitOps overlay** | Argo CD Application | `deploy_rosa_karpenter = true` |

Without a synced **NodePool**, AutoNode will not provision for pending pods (controllers + EC2NodeClass alone are not enough).

## Install-time checklist (do this before first `terraform apply`)

Set **both** flags in the initial tfvars (or use `./scripts/deploy-full-stack.sh`, which pairs them):

```hcl
# cluster stack terraform.tfvars
enable_karpenter = true

# examples/rosa-hcp-with-gitops/terraform.tfvars
deploy_rosa_karpenter = true
```

1. Push `gitops-catalog/operators/rosa-karpenter` to `gitops_repo_url` (Argo fails with `app path does not exist` if missing).
2. `enable_karpenter = true` on the **cluster** stack (IAM + `auto_node` + subnet discovery tags).
3. `deploy_rosa_karpenter = true` on the **GitOps** overlay (creates the Argo app that syncs `default-np`).

`deploy-full-stack.sh` automates (2)+(3): when cluster `enable_karpenter` / output `karpenter_enabled` is true, it sets `deploy_rosa_karpenter = true` and fails fast if the catalog path is missing.

## Prerequisites

- ROSA HCP OpenShift **≥ 4.22**
- RHCS provider with `auto_node` support
- AWS managed policy `ROSAKarpenterControllerPolicy` available in the account

## Cluster stack

```hcl
enable_karpenter = true   # default is false — opt in at install time
```

Creates:

1. **`modules/karpenter-autonode`** — IAM role with OIDC trust for `system:serviceaccount:kube-system:karpenter` + `ROSAKarpenterControllerPolicy`
2. **Cluster `auto_node`** — `mode = enabled` + `role_arn`
3. **Subnet discovery tags** (root `aws_ec2_tag`, after cluster ID exists — avoids IAM↔cluster cycle):
   - `kubernetes.io/cluster/<cluster_id>=shared` (AZ-keyed `for_each` so destroy works)
   - `kubernetes.io/role/internal-elb=1` on private subnets (BYO VPC only; new VPCs set this in `modules/vpc`)

```hcl
auto_node = {
  mode     = "enabled"
  role_arn = module.karpenter_autonode[0].role_arn
}
```

Set `enable_karpenter = false` (or omit it) to skip AutoNode IAM, `auto_node`, and discovery tags entirely.

## GitOps overlay (same initial provision)

In `examples/rosa-hcp-with-gitops` (run right after the cluster is API-ready):

```hcl
deploy_rosa_karpenter = true
```

Controllers are HCP-managed; the catalog only ships `NodePool` CRs (default NodeClass is ROSA-owned).
## Verify

```bash
oc get openshiftec2nodeclass   # default should be Ready
oc get ec2nodeclass            # synced from OpenshiftEC2NodeClass
oc get nodepool.karpenter.sh   # default-np
oc get nodeclaim
oc get nodes -l autonode=true
```

## Notes

- Default `OpenshiftEC2NodeClass` is immutable (created by ROSA when AutoNode is enabled).
- NodePools reference `kind: EC2NodeClass` / `group: karpenter.k8s.aws` with the OpenshiftEC2NodeClass **name**.
- NodePools default to **on-demand** in this catalog (override for Spot batch workloads).
- Karpenter nodes coexist with static machine pools (`autonode=true` label).
