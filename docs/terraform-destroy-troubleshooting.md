# Terraform Destroy Troubleshooting

When running `terraform destroy` on a ROSA HCP stack, you may see the following. This guide explains what they mean and how to fix failures.

## 1. Default ingress warning (informational)

```
Warning: Cannot delete default ingress
Cannot delete default ingress for cluster '...'. ROSA HCP clusters must have default ingress. It is being removed from
the Terraform state only.
```

**What it means:** ROSA HCP requires a default ingress. The RHCS provider does not delete it; it only removes the resource from Terraform state. The ingress is deleted when the cluster is deleted.

**Action:** None. This is expected. Destroy continues.

---

## 2. VPC has dependencies and cannot be deleted

```
Error: deleting EC2 VPC (vpc-...): DependencyViolation: The vpc '...' has dependencies and cannot be deleted.
```

**What it means:** The cluster (and its load balancers, ENIs, etc.) is still using the VPC. Terraform is trying to delete the VPC before the cluster is fully removed from AWS.

**Causes:**
- Cluster destroy did not wait for the cluster to be fully deleted (e.g. `disable_waiting_in_destroy = true`).
- Cluster deletion is still in progress and the destroy timeout was reached.

**Fix:**

1. **Ensure destroy waits for the cluster**  
   In your `terraform.tfvars` (or variables), set:
   ```hcl
   disable_waiting_in_destroy = false   # must be false for clean destroy
   destroy_timeout            = 90      # minutes; increase if needed
   ```
   Then run `terraform destroy` again. The provider will wait for the cluster to be fully deleted before continuing to VPC/OIDC.

2. **If destroy still fails:**  
   Wait 10–15 minutes for the cluster to finish deleting in the background, then run `terraform destroy` again. The second run should remove the VPC and OIDC config once the cluster is gone.

---

## 3. OIDC config in use

```
Error: there are clusters using OIDC config, can't delete the configuration
there are clusters using OIDC config '...', can't delete the configuration
```

**What it means:** The OCM API will not delete the OIDC config while any cluster still references it. The cluster must be fully deleted first.

**Fix:** Same as for the VPC error:

1. Set `disable_waiting_in_destroy = false` and a sufficient `destroy_timeout` (e.g. 90), then run `terraform destroy` again.
2. If it still fails, wait 10–15 minutes and run `terraform destroy` again.

---

## Recommended settings for clean destroy

In `terraform.tfvars.example` (or your own `terraform.tfvars`), use:

```hcl
disable_waiting_in_destroy = false   # do not set to true if you want one-pass destroy
destroy_timeout            = 90     # allow up to 90 minutes for cluster deletion
```

With these settings, Terraform waits for the cluster to be fully deleted before destroying the VPC and OIDC config, which avoids dependency errors in a single destroy run.
