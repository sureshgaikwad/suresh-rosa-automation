# ROSA HCP with OpenShift GitOps (day-2 overlay)

Deploy OpenShift GitOps, Argo CD applications, and optional RHOAI 3.5 / Developer Hub / Keycloak **after** a ROSA HCP cluster exists. This stack is separate from the root cluster module so install/destroy of the cluster does not depend on GitOps or `oc login`.

## One-shot deploy (recommended)

Keep two Terraform stacks / state files, but one orchestrator:

```bash
# From repo root (ocm login once beforehand, or export RHCS_TOKEN)
./scripts/deploy-full-stack.sh
```

That script:

1. Applies the **root** cluster stack (`terraform.tfvars`)
2. Waits until the cluster API accepts `oc login`
3. Injects cluster credentials via `TF_VAR_*` (not written into this overlay’s tfvars)
4. Applies this GitOps/RHOAI overlay with full-stack flags enabled

No hand-copying of `cluster_id` / passwords between tfvars.

## Manual / split usage

```bash
cd examples/rosa-hcp-with-gitops
# Feature flags live in terraform.tfvars (no cluster secrets)

export TF_VAR_cluster_id="$(terraform -chdir=../.. output -raw cluster_id)"
export TF_VAR_cluster_api_url="$(terraform -chdir=../.. output -raw cluster_api_url)"
export TF_VAR_cluster_admin_username="$(terraform -chdir=../.. output -raw cluster_admin_username)"
export TF_VAR_cluster_admin_password="$(terraform -chdir=../.. output -raw cluster_admin_password)"

terraform init
terraform apply
```

## RHOAI 3.5 flags

| Flag | What it enables |
|------|-----------------|
| `deploy_openshift_ai` | RHOAI + NFD/GPU/Serverless/Kueue/JobSet/cert-manager |
| `deploy_rhoai_maas` | Implies AI + RHCL, LWS, LB Gateway, postgres, UWM, dashboard/telemetry, COO + OpenTelemetry + MCP catalog |
| `deploy_rhoai_llmd` | Implies MaaS + KEDA + llm-d (default in this overlay’s tfvars) |

- `rhoai_genai_backend = "ogx"` (default) or `"llamastack"`
- `rhoai_channel = "stable-3.5"`
- MaaS Gateway TLS: leave `rhoai_maas_tls_secret_name` empty to auto-use the ROSA IngressController default cert (or catalog `maas-gateway-tls` fallback)
- Sample CPU vLLM image defaults to a RHOAI 3.5 digest (`:latest` is rejected by registry.redhat.io)

GPU capacity stays in the **root** `machine_pools`; this overlay installs the NVIDIA operator when AI is on.

## Destroy

```bash
cd examples/rosa-hcp-with-gitops && terraform destroy   # optional first
cd ../.. && terraform destroy
```
