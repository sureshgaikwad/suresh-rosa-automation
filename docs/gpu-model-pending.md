# GPU node and model pod stuck in Pending

## Symptom

Model pod (e.g. Mistral in `models` namespace) stays in **Pending** with events like:

```text
0/5 nodes are available: 4 Insufficient cpu, 4 Insufficient memory, 4 Insufficient nvidia.com/gpu.
```

## Cause

The pod requests **20 CPU, 80Gi memory, and 1 GPU**. Your GPU node is **g4dn.xlarge** (4 vCPU, ~16 GiB RAM, 1 GPU). That node cannot satisfy the request, so the scheduler never places the pod.

| Resource   | Pod request | g4dn.xlarge (current) | g4dn.8xlarge (recommended) |
|-----------|-------------|------------------------|-----------------------------|
| CPU       | 20          | 4                      | 32                          |
| Memory    | 80Gi        | ~16Gi                  | 128Gi                       |
| nvidia.com/gpu | 1     | 1                      | 1                           |

## Fix: use a larger GPU node type

Use a machine pool with an instance type that has enough CPU and memory, for example:

- **g4dn.8xlarge** – 32 vCPU, 128 GiB, 1x T4 GPU (fits 20 CPU + 80Gi)
- **g4dn.12xlarge** – 48 vCPU, 192 GiB, 4x T4 (more headroom)

In your Terraform `terraform.tfvars` (or wherever you define `machine_pools`), set the GPU pool to a larger instance type:

```hcl
machine_pools = {
  # ... other pools ...

  "gpu-pool" = {
    name = "gpu-pool"
    aws_node_pool = {
      instance_type = "g4dn.8xlarge"   # was g4dn.xlarge
      tags          = {}
    }
    replicas    = 1
    auto_repair = true
    labels = {
      "node-type" = "gpu"
    }
    taints = [
      {
        key           = "nvidia.com/gpu"
        value         = "true"
        schedule_type = "NoSchedule"
      }
    ]
  }
}
```

Then run `terraform apply`. After the new GPU node(s) join and the old ones drain, the model pod should schedule.

## Alternative: reduce model resource requests

If you must keep **g4dn.xlarge**, you would need to change the model’s InferenceService (or deployment) in your GitOps repo so it requests less CPU and memory (e.g. 4 CPU, 16Gi). Many LLM serving configs need large memory for weights, so this may not be viable for Mistral 24B; prefer upgrading the GPU node type instead.
