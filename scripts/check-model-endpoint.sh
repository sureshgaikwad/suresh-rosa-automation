#!/usr/bin/env bash
set -euo pipefail

# Validate OpenAI-compatible endpoint health and basic SLO signal.

API_BASE="${API_BASE:-http://qwen-25-7b-predictor.models.svc.cluster.local:8080/v1}"
MODEL_ID="${MODEL_ID:-qwen-25-7b}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-20}"
WARN_LATENCY_MS="${WARN_LATENCY_MS:-2500}"
AUTH_HEADER="${AUTH_HEADER:-}"
NAMESPACE="${NAMESPACE:-models}"

require_tools() {
  command -v curl >/dev/null 2>&1 || { echo "ERROR: curl required"; exit 1; }
  command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required"; exit 1; }
}

check_models() {
  echo "==> Checking model catalog at ${API_BASE}/models"
  local payload
  if [ -n "$AUTH_HEADER" ]; then
    if ! payload="$(curl -sS --max-time "$TIMEOUT_SECONDS" -H "Authorization: ${AUTH_HEADER}" "${API_BASE}/models")"; then
      return 1
    fi
  else
    if ! payload="$(curl -sS --max-time "$TIMEOUT_SECONDS" "${API_BASE}/models")"; then
      return 1
    fi
  fi
  echo "$payload" | jq -e ".data[] | select(.id == \"${MODEL_ID}\")" >/dev/null
  echo "    Model ${MODEL_ID} found"
}

check_completion_latency() {
  echo "==> Checking completion path at ${API_BASE}/chat/completions"
  local start_ms
  local end_ms
  local elapsed_ms
  start_ms="$(date +%s%3N)"
  local response
  if [ -n "$AUTH_HEADER" ]; then
    if ! response="$(curl -sS --max-time "$TIMEOUT_SECONDS" \
      -H "Authorization: ${AUTH_HEADER}" \
      -H "Content-Type: application/json" \
      -d "{\"model\":\"${MODEL_ID}\",\"messages\":[{\"role\":\"user\",\"content\":\"ping\"}],\"max_tokens\":4}" \
      "${API_BASE}/chat/completions")"; then
      return 1
    fi
  else
    if ! response="$(curl -sS --max-time "$TIMEOUT_SECONDS" \
      -H "Content-Type: application/json" \
      -d "{\"model\":\"${MODEL_ID}\",\"messages\":[{\"role\":\"user\",\"content\":\"ping\"}],\"max_tokens\":4}" \
      "${API_BASE}/chat/completions")"; then
      return 1
    fi
  fi
  end_ms="$(date +%s%3N)"
  elapsed_ms=$((end_ms - start_ms))

  echo "$response" | jq -e '.choices[0].message.content' >/dev/null
  echo "    Completion latency: ${elapsed_ms}ms"
  if [ "$elapsed_ms" -gt "$WARN_LATENCY_MS" ]; then
    echo "WARNING: Latency ${elapsed_ms}ms is above warning threshold ${WARN_LATENCY_MS}ms"
  fi
}

check_in_cluster() {
  command -v oc >/dev/null 2>&1 || {
    echo "ERROR: Cannot reach svc DNS locally and 'oc' is not available for in-cluster check"
    exit 1
  }
  echo "==> Local DNS/network cannot reach ${API_BASE}; running in-cluster probe pod in namespace ${NAMESPACE}"
  oc -n "$NAMESPACE" delete pod model-endpoint-check --ignore-not-found=true --wait=true >/dev/null 2>&1 || true
  oc -n "$NAMESPACE" run model-endpoint-check --image=curlimages/curl:8.12.1 --restart=Never \
    --command -- sh -c "curl -sS '${API_BASE}/models' && echo && curl -sS -H 'Content-Type: application/json' -d '{\"model\":\"${MODEL_ID}\",\"messages\":[{\"role\":\"user\",\"content\":\"ping\"}],\"max_tokens\":4}' '${API_BASE}/chat/completions'" >/dev/null
  local elapsed=0
  local phase=""
  while [ "$elapsed" -lt "$TIMEOUT_SECONDS" ]; do
    phase="$(oc -n "$NAMESPACE" get pod model-endpoint-check -o jsonpath='{.status.phase}' 2>/dev/null || true)"
    if [ "$phase" = "Succeeded" ] || [ "$phase" = "Running" ] || [ "$phase" = "Failed" ]; then
      break
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  local logs
  logs="$(oc -n "$NAMESPACE" logs model-endpoint-check)"
  echo "$logs" | jq -e "select(.data != null) | .data[] | select(.id == \"${MODEL_ID}\")" >/dev/null
  echo "$logs" | jq -e 'select(.choices != null) | .choices[0].message.content' >/dev/null
  oc -n "$NAMESPACE" delete pod model-endpoint-check --wait=true >/dev/null 2>&1 || true
  echo "==> In-cluster endpoint checks passed"
}

main() {
  require_tools
  if ! check_models; then
    check_in_cluster
    return
  fi
  if ! check_completion_latency; then
    check_in_cluster
    return
  fi
  echo "==> Endpoint checks passed"
}

main
