#!/usr/bin/env bash
set -euo pipefail

# Manage temporary ArgoCD autosync windows for bootstrap/hardening.
# The script patches Applications in openshift-gitops namespace.

ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-openshift-gitops}"
ACTION="${1:-}"

# Keep the default list aligned with the architecture rollout order.
DEFAULT_APPS="keycloak-operator developer-hub-operator openshift-devspaces-operator openshift-ai-operator ai-model"
APPS="${APPS:-$DEFAULT_APPS}"
WAIT_SECONDS="${WAIT_SECONDS:-300}"
KUBECONFIG_PATH="${KUBECONFIG:-}"

usage() {
  cat <<EOF
Usage:
  $0 freeze
  $0 unfreeze
  $0 status

Environment overrides:
  ARGOCD_NAMESPACE   Argo namespace (default: openshift-gitops)
  APPS               Space-separated Argo Application names
  WAIT_SECONDS       Wait timeout when unfreezing (default: 300)
  KUBECONFIG         Optional kubeconfig path

Examples:
  APPS="keycloak-operator developer-hub-operator" $0 freeze
  APPS="keycloak-operator developer-hub-operator openshift-devspaces-operator" $0 unfreeze
EOF
}

oc_cmd() {
  if [ -n "$KUBECONFIG_PATH" ]; then
    oc --kubeconfig="$KUBECONFIG_PATH" "$@"
  else
    oc "$@"
  fi
}

require_tools() {
  command -v oc >/dev/null 2>&1 || { echo "ERROR: oc is required"; exit 1; }
}

set_manual_sync() {
  local app="$1"
  echo "==> Setting manual sync for app: $app"
  # Remove spec.syncPolicy.automated while preserving other syncPolicy fields.
  oc_cmd -n "$ARGOCD_NAMESPACE" patch applications.argoproj.io "$app" --type merge \
    -p '{"spec":{"syncPolicy":{"automated":null}}}'
}

set_auto_sync() {
  local app="$1"
  echo "==> Enabling autosync for app: $app"
  oc_cmd -n "$ARGOCD_NAMESPACE" patch applications.argoproj.io "$app" --type merge \
    -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true,"allowEmpty":false}}}}'
}

wait_healthy() {
  local app="$1"
  local elapsed=0
  while [ "$elapsed" -lt "$WAIT_SECONDS" ]; do
    local health
    local sync
    health="$(oc_cmd -n "$ARGOCD_NAMESPACE" get applications.argoproj.io "$app" -o jsonpath='{.status.health.status}' 2>/dev/null || true)"
    sync="$(oc_cmd -n "$ARGOCD_NAMESPACE" get applications.argoproj.io "$app" -o jsonpath='{.status.sync.status}' 2>/dev/null || true)"
    if [ "$health" = "Healthy" ] && [ "$sync" = "Synced" ]; then
      echo "    App $app is Healthy/Synced"
      return 0
    fi
    sleep 10
    elapsed=$((elapsed + 10))
    echo "    Waiting for $app (health=${health:-Unknown}, sync=${sync:-Unknown}) ${elapsed}s/${WAIT_SECONDS}s"
  done
  echo "WARNING: Timed out waiting for $app to become Healthy/Synced"
  return 1
}

freeze() {
  for app in $APPS; do
    set_manual_sync "$app"
  done
}

unfreeze() {
  for app in $APPS; do
    set_auto_sync "$app"
    wait_healthy "$app"
  done
}

status() {
  for app in $APPS; do
    echo "==> $app"
    oc_cmd -n "$ARGOCD_NAMESPACE" get applications.argoproj.io "$app" \
      -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,AUTOSYNC:.spec.syncPolicy.automated.prune --no-headers 2>/dev/null || \
      echo "    Not found"
  done
}

main() {
  require_tools
  case "$ACTION" in
    freeze)   freeze ;;
    unfreeze) unfreeze ;;
    status)   status ;;
    *) usage; exit 1 ;;
  esac
}

main
