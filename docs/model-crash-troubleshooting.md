# Model crashing in the `models` project

## Symptom

The model pod (e.g. Mistral in the `models` namespace) is in **CrashLoopBackOff** or exits with **OOMKilled**.

## Common causes and fixes

### 1. Out of memory (OOMKilled)

The container is using more memory than allowed, so the node kills it.

**Fix:**

- Set **memory limits** on the InferenceService (or deployment) so the pod is not over-committed, and ensure the limit is at least as large as the model needs (e.g. 80Gi for Mistral 24B).
- Use a **GPU node with enough RAM** (e.g. **g4dn.8xlarge** with 128Gi). If the node has less memory than the pod request, the pod may schedule but then OOM when loading the model. See [GPU node and model pod stuck in Pending](gpu-model-pending.md).

In your **gitops-catalog** repo, in the manifest at `ai-models/mistral/`, add or adjust the predictor resources so that **limits** are set and match your node capacity:

```yaml
spec:
  predictor:
    model:  # or container, depending on your predictor type
      resources:
        requests:
          cpu: "20"
          memory: 80Gi
          nvidia.com/gpu: "1"
        limits:
          cpu: "20"
          memory: 80Gi
          nvidia.com/gpu: "1"
```

Use the same value for `memory` in both `requests` and `limits` to avoid overcommit. If the pod is still OOMKilled, increase the memory (and use a larger node type if needed).

### 2. Pod never starts (Pending)

If the pod stays **Pending** with events like `Insufficient cpu` / `Insufficient memory` / `Insufficient nvidia.com/gpu`, the node pool is too small. See [GPU node and model pod stuck in Pending](gpu-model-pending.md).

### 3. BFloat16 not supported on Tesla T4 (compute capability 7.5)

**Error:**  
`ValueError: Bfloat16 is only supported on GPUs with compute capability of at least 8.0. Your Tesla T4 GPU has compute capability 7.5. You can use float16 instead by explicitly setting the dtype flag in CLI, for example: --dtype=half.`

**Cause:** T4 GPUs (e.g. on g4dn instances) do not support BFloat16; they need compute capability 8.0+ (e.g. A10, A100). The default or configured dtype is bfloat16.

**Fix:** Force float16 in your InferenceService by adding the dtype argument to the predictor. In your **gitops-catalog** repo, in the manifest at `ai-models/mistral/`, add under the predictor (e.g. under `spec.predictor.model.args` or the container `args`):

```yaml
args:
  - --dtype=half
# or: - --dtype=float16
```

Example for a `model` predictor:

```yaml
spec:
  predictor:
    model:
      modelFormat:
        name: huggingface
      args:
        - --dtype=half
      # ... storageUri, resources, etc.
```

After updating, commit and push; ArgoCD will sync and the model server will use float16 instead of bfloat16.

### 4. Wrong node size

Ensure your GPU machine pool uses an instance type that can satisfy the model's requests (e.g. **g4dn.8xlarge** for 20 CPU + 80Gi + 1 GPU). Smaller types like **g4dn.xlarge** (4 CPU, ~16Gi) will cause Pending or OOM.

## Reference manifest

A reference InferenceService with safe resource requests/limits and `--dtype=half` for T4 is in **manifests/ai-model-inferenceservice-example.yaml**. Copy the `resources` and `args` sections into your gitops-catalog `ai-models/mistral` manifest, or replace your manifest with that file (then set `storageUri` / runtime as in your current setup).

## Where to apply changes

- The model is deployed by ArgoCD from your **gitops-catalog** repo, path **ai-models/mistral**, namespace **models**.
- Edit the InferenceService (or deployment) in that repo, commit and push; ArgoCD will sync and the updated resources will apply.
