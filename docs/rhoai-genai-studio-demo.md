# RHOAI GenAI Studio demo (guardrails + MLflow tracing)

Based on [micytao/rhoai-demo-guide](https://github.com/micytao/rhoai-demo-guide): platform **NemoGuardrails** on GenAI Studio / OGX Playground, with **MLflow** OTEL tracing.

## What we already had vs what this adds

| Piece | Before | Now |
|-------|--------|-----|
| RHOAI 3.5 + OGX DSC toggle | ✅ `rhoai_genai_backend = "ogx"` | unchanged |
| MaaS gateway + sample model | ✅ `deploy_rhoai_maas` | implied by demo flag |
| Dashboard `genAiStudio` | ✅ via `openshift-ai-maas` | unchanged |
| MLflow operator | ❌ | ✅ `components/mlflow-enable` |
| `demo` project + MLflow CR | ❌ | ✅ `operators/rhoai-genai-studio-demo` |
| Playground / NemoGuardrails / OTEL workarounds | ❌ | ✅ `scripts/setup-genai-studio-mlflow-tracing.sh` |
| Live demo script | ❌ | ✅ [rhoai-genai-studio-demo-flow.md](./rhoai-genai-studio-demo-flow.md) |

## Enable (day-2 overlay)

In `examples/rosa-hcp-with-gitops`:

```hcl
deploy_rhoai_genai_studio_demo = true
# implies: deploy_rhoai_maas, OGX backend, MLflow operator
# keep a sample model subscribed for the playground:
deploy_rhoai_maas_sample_model = true
```

Apply the overlay, wait for Argo apps (`openshift-ai-operator`, `openshift-ai-maas`, `rhoai-genai-studio-demo`) to sync.

## Run the workaround script

Playground creation + OTEL patches are **intentionally imperative** (operator-proof `PYTHONPATH` / `opentelemetry-instrument` patterns from the upstream guide):

```bash
# oc login as cluster-admin first
./scripts/setup-genai-studio-mlflow-tracing.sh --namespace demo

# or dry-run
./scripts/setup-genai-studio-mlflow-tracing.sh --namespace demo --dry-run
```

The script auto-detects the MaaS gateway route and a subscribed model. Override if needed:

```bash
./scripts/setup-genai-studio-mlflow-tracing.sh --namespace demo \
  --maas-gateway "https://maas.apps.example.com" \
  --model "qwen25-05b-maas"
```

## Demo

Follow [rhoai-genai-studio-demo-flow.md](./rhoai-genai-studio-demo-flow.md) (5 acts: baseline → enable guardrails → blocked prompts → save agent → MLflow traces).

## Upstream

- Guide: https://github.com/micytao/rhoai-demo-guide
- Animated diagram: https://micytao.github.io/rhoai-demo-guide/mlflow-tracing-flow.html
