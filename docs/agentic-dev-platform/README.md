# Agentic Dev Platform Implementation

This package implements a GitOps-friendly architecture that connects:

- OpenShift GitOps (ArgoCD)
- Keycloak (OIDC identity and group claims)
- Red Hat Developer Hub (software templates + entry point)
- OpenShift Dev Spaces (workspace runtime)
- OpenShift AI model endpoint (OpenAI-compatible API)

## Directory Layout

- `scripts/argocd-sync-control.sh`: Temporary freeze/unfreeze of Argo autosync for bootstrap windows.
- `scripts/check-model-endpoint.sh`: Health and latency smoke checks for model endpoint.
- `scripts/gitops-reconcile-agentic-stack.sh`: Progressive autosync re-enable with health gates.
- `assets/agentic-dev-platform/argocd/sync-wave-overrides.yaml`: App dependency order.
- `assets/agentic-dev-platform/keycloak/realm-agentic-platform.json`: Realm, clients, and groups.
- `assets/agentic-dev-platform/rbac/*.yaml`: Group-to-permission bindings.
- `assets/agentic-dev-platform/model/model-service-contract.yaml`: Shared endpoint/model contract.
- `assets/agentic-dev-platform/devspaces/devworkspace-ostoy-ai.yaml`: Golden workspace template.
- `assets/agentic-dev-platform/developer-hub/*`: Hub template and app-config snippet.
- `docs/agentic-dev-platform/pilot-kpis.md`: Pilot and stage-gate metrics.

## 1) Bootstrap Guardrail Mode (Argo)

Disable autosync only for sensitive applications during integration:

```bash
./scripts/argocd-sync-control.sh freeze
./scripts/argocd-sync-control.sh status
```

The default freeze scope is:

1. `keycloak-operator`
2. `developer-hub-operator`
3. `openshift-devspaces-operator`
4. `openshift-ai-operator`
5. `ai-model`

Apply dependency hints:

```bash
oc apply -f assets/agentic-dev-platform/argocd/sync-wave-overrides.yaml
```

## 2) OIDC and RBAC Alignment

Import Keycloak realm/client/group model:

```bash
oc -n rhbk create configmap agentic-realm \
  --from-file=assets/agentic-dev-platform/keycloak/realm-agentic-platform.json
```

Apply platform RBAC:

```bash
oc apply -f assets/agentic-dev-platform/rbac/developer-hub-rbac.yaml
oc apply -f assets/agentic-dev-platform/rbac/devspaces-rbac.yaml
```

## 3) Shared OpenShift AI Model Contract

Publish contract:

```bash
oc apply -f assets/agentic-dev-platform/model/model-service-contract.yaml
```

Validate endpoint:

```bash
./scripts/check-model-endpoint.sh
```

## 4) Golden Dev Spaces Workspace

Apply template and starter workspace:

```bash
oc apply -f assets/agentic-dev-platform/devspaces/devworkspace-ostoy-ai.yaml
```

Expected behavior:

- OSToy repository is cloned.
- Continue configuration is written at `~/.continue/config.json`.
- Model endpoint smoke test runs.
- Dependency install runs.

After opening editor, run:

- `Continue: Rebuild Codebase Index`

## 5) Developer Hub Golden Path

Apply template and copy app-config snippet into your Developer Hub config:

```bash
oc apply -f assets/agentic-dev-platform/developer-hub/template-ostoy-ai-starter.yaml
```

Merge snippet from:

- `assets/agentic-dev-platform/developer-hub/app-config-agentic-snippet.yaml`

Outcome:

- Developers can bootstrap an AI-assisted starter.
- Developers are routed into Dev Spaces.
- Hub auth uses Keycloak OIDC claims.

## 6) GitOps Reconciliation

After manifest changes are committed and reviewed in Git, progressively re-enable autosync:

```bash
./scripts/gitops-reconcile-agentic-stack.sh
```

This script enforces:

- clean git working tree before proceeding,
- ordered autosync enablement,
- per-app Healthy/Synced gating,
- model contract presence validation.

## 7) Pilot Rollout

Use `docs/agentic-dev-platform/pilot-kpis.md` to run pilot acceptance:

- time-to-first-PR,
- workspace startup success,
- model availability/latency,
- multi-file AI edit success.

Promote from `dev` to `stage` to `prod` only after KPI thresholds are met.
