# Karpenter AutoNode IAM (ROSA HCP)

Creates the AWS IAM role required to enable **Red Hat build of Karpenter** (AutoNode) on a ROSA HCP cluster (OpenShift ≥ 4.22).

The Karpenter controller runs in the **hosted control plane** — there is no in-cluster operator Subscription. After this role exists, enable AutoNode on the cluster via:

```hcl
auto_node = {
  mode     = "enabled"
  role_arn = module.karpenter_autonode[0].role_arn
}
```

Subnet discovery tags (`kubernetes.io/cluster/<id>` and `internal-elb`) are applied at the **root** stack after the cluster exists (not in this module), to avoid a Terraform cycle with `auto_node.role_arn`.

NodePool manifests are managed via GitOps (`operators/rosa-karpenter` in the gitops-catalog). The default `OpenshiftEC2NodeClass` is created by ROSA when AutoNode is enabled.
