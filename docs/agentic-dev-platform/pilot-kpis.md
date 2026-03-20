# Pilot KPIs and Hardening Backlog

Use this checklist for the first cohort rollout of the agentic development platform.

## Pilot Scope

- Cohort size: 5-15 developers
- Reference repo: `https://github.com/sureshgaikwad/ostoy`
- Workspace type: `ostoy-ai-template`
- Auth path: Keycloak OIDC only
- AI backend: OpenShift AI model (`qwen-25-7b`)

## KPI Targets

| KPI | Target | How to measure |
|---|---:|---|
| Time to first successful PR | <= 30 minutes | Developer onboarding session timing |
| Workspace startup success | >= 98% | Dev Spaces workspace events/status |
| Model endpoint availability | >= 99.5% | `check-model-endpoint.sh` cron job logs |
| P95 completion latency | <= 2500ms | Endpoint probe logs and tracing |
| Multi-file AI task success | >= 80% | Prompt outcomes across 5 standard tasks |
| Argo drift incidents | 0 unmanaged drifts | Argo app sync/drift reports |

## Daily Pilot Checks

1. Run model endpoint probe.
2. Sample 3 active workspaces for extension health and codebase index completion.
3. Verify Argo applications remain Healthy/Synced.
4. Review Keycloak login failures and token errors.
5. Capture developer-reported friction points.

## Hardening Backlog Template

Track issues under four buckets:

- **Identity**: claim mapping, session timeout, group propagation delays.
- **Workspace**: startup failures, storage persistence, extension conflicts.
- **Model**: endpoint saturation, prompt truncation, model-id drift.
- **GitOps**: reconciliation race conditions, overlay collisions, sync windows.

Each issue should include:

- severity,
- reproducible steps,
- owner,
- mitigation,
- fix ETA.

## Promotion Gates

Move from `dev` to `stage` only if:

- all KPI targets pass for 5 consecutive days,
- no P1 incidents in last 7 days,
- hardening backlog has no open critical items.

Move from `stage` to `prod` only if:

- stage soak test runs for at least 2 weeks,
- rollback runbook is validated,
- security review signs off on secret handling and RBAC.
