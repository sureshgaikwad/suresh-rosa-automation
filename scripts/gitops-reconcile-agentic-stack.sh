#!/usr/bin/env bash
set -euo pipefail

# Progressive sync re-enable procedure for agentic platform apps.

ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-openshift-gitops}"
WAIT_SECONDS="${WAIT_SECONDS:-300}"
KUBECONFIG_PATH="${KUBECONFIG:-}"

ORDERED_APPS=(
  "keycloak-operator"
  "developer-hub-operator"
  "openshift-devspaces-operator"
  "openshift-ai-operator"
  "ai-model"
)

oc_cmd() {
  if [ -n "$KUBECONFIG_PATH" ]; then
    oc --kubeconfig="$KUBECONFIG_PATH" "$@"
  else
    oc "$@"
  fi
}

require_tools() {
  command -v oc >/dev/null 2>&1 || { echo "ERROR: oc required"; exit 1; }
  command -v git >/dev/null 2>&1 || { echo "ERROR: git required"; exit 1; }
}

ensure_clean_git() {
  if [ -n "$(git status --porcelain)" ]; then
    echo "ERROR: Git working tree is not clean. Commit/review changes before reconciliation."
    exit 1
  fi
}

enable_app_autosync() {
  local app="$1"
  oc_cmd -n "$ARGOCD_NAMESPACE" patch applications.argoproj.io "$app" --type merge \
    -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true,"allowEmpty":false}}}}'
}

wait_app_healthy() {
  local app="$1"
  local elapsed=0
  while [ "$elapsed" -lt "$WAIT_SECONDS" ]; do
    local health
    local sync
    health="$(oc_cmd -n "$ARGOCD_NAMESPACE" get applications.argoproj.io "$app" -o jsonpath='{.status.health.status}' 2>/dev/null || true)"
    sync="$(oc_cmd -n "$ARGOCD_NAMESPACE" get applications.argoproj.io "$app" -o jsonpath='{.status.sync.status}' 2>/dev/null || true)"
    if [ "$health" = "Healthy" ] && [ "$sync" = "Synced" ]; then
      echo "    $app is Healthy/Synced"
      return 0
    fi
    sleep 10
    elapsed=$((elapsed + 10))
    echo "    Waiting on $app (health=${health:-Unknown} sync=${sync:-Unknown}) ${elapsed}s/${WAIT_SECONDS}s"
  done
  echo "ERROR: $app did not reach Healthy/Synced"
  return 1
}

validate_model_contract() {
  echo "==> Validating model contract config"
  oc_cmd -n models get configmap agentic-model-contract >/dev/null
  oc_cmd -n models get configmap agentic-model-contract -o jsonpath='{.data.OPENAI_MODEL_ID}' | grep -q .
}

main() {
  require_tools
  ensure_clean_git

  echo "==> Starting progressive Argo reconciliation for agentic stack"
  for app in "${ORDERED_APPS[@]}"; do
    echo "==> Enabling autosync: $app"
    enable_app_autosync "$app"
    wait_app_healthy "$app"
  done

  validate_model_contract
  echo "==> Reconciliation complete"
}

main
