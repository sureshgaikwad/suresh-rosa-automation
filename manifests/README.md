# Manifests

Reference manifests for GitOps and cluster configuration.

## Developer Hub – ArgoCD ComparisonError (missing files)

**Problem:** Developer Hub operator application shows **ComparisonError**:  
`demo-project-namespace.yaml: no such file or directory` (Kustomize fails).

**Cause:** The root `operators/developer-hub/kustomization.yaml` lists resources at the root of `developer-hub/`, but the files actually live under `operators/developer-hub/base/`.

**Fix (applied):** The ArgoCD application path was changed from `operators/developer-hub` to `operators/developer-hub/base`. Terraform and the live app have been updated. ArgoCD syncs the YAML files from `base/` and the application should clear the error and progress to Synced.

**Optional:** If you prefer to use Kustomize explicitly for the base folder, add `operators/developer-hub/base/kustomization.yaml` in your gitops-catalog repo using the content in `developer-hub-base-kustomization.yaml` in this folder.

## OpenShift AI – DataScienceCluster v2 (admission webhook fix)

**Problem:** ArgoCD shows:  
`admission webhook "datasciencecluster-v1-validator.opendatahub.io" denied the request: Managed is no longer supported as a managementState`

**Cause:** OpenShift AI 3.2’s **v1** DataScienceCluster API is restricted; the v1 validator no longer accepts `managementState: Managed`.

**Fix:**

1. **Already applied on your cluster:** The v2 `DataScienceCluster` from `openshift-ai-datasciencecluster-v2.yaml` was applied so OpenShift AI can reconcile.

2. **Update your GitOps repo** so ArgoCD stops reapplying the old v1 manifest and stays in sync:
   - In your **gitops-catalog** repo, replace the content of  
     `operators/openshift-ai/datasciencecluster.yaml`  
     with the content of  
     `manifests/openshift-ai-datasciencecluster-v2.yaml`  
     from this repo.
   - Commit and push. After the next sync, the OpenShift AI ArgoCD application will use the v2 spec and the admission error will stop.

Summary of changes in the v2 manifest:

- `apiVersion`: `datasciencecluster.opendatahub.io/v1` → `datasciencecluster.opendatahub.io/v2`
- v2 component names: e.g. `datasciencepipelines` → `aipipelines`; v1-only components (e.g. `codeflare`, `modelmeshserving`) removed to match v2.
- `kueue.managementState`: in v2 only `Unmanaged` or `Removed` are allowed; set to `Unmanaged` so you can use an external Kueue operator if needed.

## Model crashing in `models` project (CrashLoopBackOff / OOMKilled)

**Problem:** The model pod (e.g. Mistral in the `models` namespace) crashes or is OOMKilled.

**Fix:**

1. **Set resource limits** in your model’s InferenceService so memory is capped and the pod can schedule on a node with enough capacity. Use the reference manifest in **manifests/ai-model-inferenceservice-example.yaml** and copy the `resources` block into your gitops-catalog repo at `ai-models/mistral/` (merge into your existing InferenceService).
2. **On Tesla T4 (g4dn):** If you see `Bfloat16 is only supported on GPUs with compute capability of at least 8.0`, add `args: [--dtype=half]` to the predictor so the model uses float16 instead of bfloat16. The example manifest includes this.
3. **Use a GPU node that fits the request** (e.g. **g4dn.8xlarge** for 20 CPU + 80Gi + 1 GPU). If the node is too small, see [GPU node and model pod stuck in Pending](../docs/gpu-model-pending.md).
4. Full steps and alternatives: [Model crash troubleshooting](../docs/model-crash-troubleshooting.md).
