#!/usr/bin/env bash
# Deploy ROSA HCP cluster + GitOps/RHOAI day-2 stack in one go.
#
# Stacks stay separate (two Terraform roots / two state files).
# This script is the only glue: cluster apply → wait for API → GitOps apply.
#
# Usage:
#   ./scripts/deploy-full-stack.sh
#
# Optional env:
#   RHCS_TOKEN              OCM token (auto: ocm token)
#   TERRAFORM_DIR           Cluster stack directory (default: repo root)
#   SKIP_CLUSTER_APPLY=1    Only run GitOps overlay (cluster already up)
#   SKIP_GITOPS_APPLY=1     Only run cluster apply
#   API_WAIT_TIMEOUT_SEC    Max wait for cluster API (default: 1800)
#   TF_CMD                  terraform binary (default: terraform)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WORK_DIR="$(cd "${TERRAFORM_DIR:-${REPO_ROOT}}" && pwd)"
GITOPS_DIR="${REPO_ROOT}/examples/rosa-hcp-with-gitops"
GITOPS_TFVARS="${GITOPS_DIR}/terraform.tfvars"
TF="${TF_CMD:-terraform}"
API_WAIT_TIMEOUT_SEC="${API_WAIT_TIMEOUT_SEC:-1800}"
API_WAIT_INTERVAL_SEC="${API_WAIT_INTERVAL_SEC:-30}"

log() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' is required but not found in PATH"
}

ensure_rhcs_token() {
  if [[ -n "${RHCS_TOKEN:-}" ]]; then
    return 0
  fi
  if command -v ocm >/dev/null 2>&1; then
    log "RHCS_TOKEN unset; obtaining via 'ocm token'"
    RHCS_TOKEN="$(ocm token)" || die "ocm token failed; run 'ocm login' first"
    export RHCS_TOKEN
    return 0
  fi
  die "RHCS_TOKEN is not set and 'ocm' is not available. Export RHCS_TOKEN or install/login ocm."
}

tf_apply() {
  local dir="$1"
  shift
  local -a args=(-chdir="${dir}" apply -auto-approve -input=false)
  if [[ -f "${dir}/terraform.tfvars" ]]; then
    args+=(-var-file="${dir}/terraform.tfvars")
  fi
  if [[ -n "${TERRAFORM_APPLY_EXTRA_VARS:-}" ]]; then
    # shellcheck disable=SC2206
    local extra=(${TERRAFORM_APPLY_EXTRA_VARS})
    args+=("${extra[@]}")
  fi
  args+=("$@")
  log "terraform apply (${dir})"
  "$TF" "${args[@]}"
}

wait_for_cluster_api() {
  local api_url="$1" user="$2" password="$3"
  local deadline=$((SECONDS + API_WAIT_TIMEOUT_SEC))
  local kubeconfig="/tmp/rosa-full-stack-kubeconfig-$$"

  log "Waiting for cluster API (${api_url}), timeout ${API_WAIT_TIMEOUT_SEC}s"
  require_cmd oc

  while (( SECONDS < deadline )); do
    if oc login --username="${user}" --password="${password}" "${api_url}" \
         --insecure-skip-tls-verify --kubeconfig="${kubeconfig}" >/dev/null 2>&1; then
      if oc --kubeconfig="${kubeconfig}" get --raw=/readyz >/dev/null 2>&1 \
        || oc --kubeconfig="${kubeconfig}" get nodes >/dev/null 2>&1; then
        rm -f "${kubeconfig}"
        log "Cluster API is reachable"
        return 0
      fi
    fi
    rm -f "${kubeconfig}"
    log "API not ready yet; retrying in ${API_WAIT_INTERVAL_SEC}s..."
    sleep "${API_WAIT_INTERVAL_SEC}"
  done

  die "Cluster API not reachable within ${API_WAIT_TIMEOUT_SEC}s: ${api_url}"
}

write_gitops_feature_tfvars() {
  # Feature flags only — no cluster credentials written to disk.
  if [[ ! -f "${GITOPS_TFVARS}" ]]; then
    cp "${GITOPS_DIR}/terraform.tfvars.example" "${GITOPS_TFVARS}"
  fi

  python3 - "${GITOPS_TFVARS}" <<'PY'
import re, sys
path = sys.argv[1]
with open(path) as f:
    text = f.read()

def ensure_bool(text, name, value="true"):
    pattern = rf'(?m)^#?\s*{re.escape(name)}\s*=\s*(true|false)\s*$'
    line = f"{name} = {value}"
    if re.search(pattern, text):
        return re.sub(pattern, line, text, count=1)
    return text.rstrip() + f"\n\n{line}\n"

def ensure_str(text, name, value):
    pattern = rf'(?m)^#?\s*{re.escape(name)}\s*=\s*".*?"\s*$'
    line = f'{name} = "{value}"'
    if re.search(pattern, text):
        return re.sub(pattern, line, text, count=1)
    return text.rstrip() + f"\n{line}\n"

text = ensure_bool(text, "deploy_openshift_gitops", "true")
text = ensure_bool(text, "deploy_vote_application", "false")
text = ensure_bool(text, "deploy_rhoai_llmd", "true")
text = ensure_bool(text, "deploy_rhoai_maas_sample_model", "true")
text = ensure_bool(text, "deploy_rhoai_llmd_keda", "true")
text = ensure_bool(text, "deploy_openshift_lightspeed", "true")
text = ensure_str(text, "rhoai_channel", "stable-3.5")
text = ensure_str(text, "rhoai_genai_backend", "ogx")
text = ensure_str(text, "gitops_repo_url", "https://github.com/sureshgaikwad/gitops-catalog")

# Strip committed credential placeholders so TF_VAR_* from the orchestrator win cleanly.
for name in ("cluster_id", "cluster_api_url", "cluster_admin_username", "cluster_admin_password"):
    text = re.sub(rf'(?m)^#?\s*{name}\s*=\s*".*?"\s*\n?', "", text)

with open(path, "w") as f:
    f.write(text.rstrip() + "\n")
print(f"updated feature flags in {path}")
PY
}

tf_output_raw() {
  # Tolerate missing/null outputs (common after cluster import).
  "$TF" -chdir="${WORK_DIR}" output -raw "$1" 2>/dev/null || true
}

ensure_cluster_admin_password() {
  # After a tainted/re-imported cluster, admin password may be absent from state.
  if [[ -n "${TF_VAR_cluster_admin_password:-}" ]]; then
    return 0
  fi
  if [[ -n "${CLUSTER_ADMIN_PASSWORD:-}" ]]; then
    TF_VAR_cluster_admin_password="${CLUSTER_ADMIN_PASSWORD}"
    export TF_VAR_cluster_admin_password
    return 0
  fi
  if [[ -f /tmp/sgaikwad-cluster-admin.pass ]]; then
    TF_VAR_cluster_admin_password="$(cat /tmp/sgaikwad-cluster-admin.pass)"
    export TF_VAR_cluster_admin_password
    return 0
  fi

  local cluster_name
  cluster_name="$(grep -E '^\s*cluster_name\s*=' "${WORK_DIR}/terraform.tfvars" | head -1 | sed -E 's/.*=\s*"([^"]+)".*/\1/' || true)"
  cluster_name="${cluster_name:-${TF_VAR_cluster_id}}"
  if command -v rosa >/dev/null 2>&1 && [[ -n "${cluster_name}" ]]; then
    log "cluster_admin_password missing from Terraform state; creating via 'rosa create admin'"
    local pass
    pass="$(openssl rand -base64 18 | tr -d '=+/')"
    # Best-effort: delete existing HTPasswd cluster-admin then recreate (idempotent enough for recovery).
    rosa delete admin -c "${cluster_name}" -y >/dev/null 2>&1 || true
    rosa create admin -c "${cluster_name}" -p "${pass}" >/dev/null
    TF_VAR_cluster_admin_password="${pass}"
    export TF_VAR_cluster_admin_password
    umask 077
    printf '%s\n' "${pass}" > /tmp/sgaikwad-cluster-admin.pass
    return 0
  fi

  die "No cluster admin password. Set CLUSTER_ADMIN_PASSWORD, or ensure Terraform output cluster_admin_password exists."
}

export_cluster_tf_vars() {
  log "Reading cluster outputs for GitOps overlay"
  export TF_VAR_cluster_id
  export TF_VAR_cluster_api_url
  export TF_VAR_cluster_admin_username
  export TF_VAR_cluster_admin_password
  export TF_VAR_aws_region
  TF_VAR_cluster_id="$(tf_output_raw cluster_id)"
  TF_VAR_cluster_api_url="$(tf_output_raw cluster_api_url)"
  TF_VAR_cluster_admin_username="$(tf_output_raw cluster_admin_username)"
  TF_VAR_cluster_admin_password="$(tf_output_raw cluster_admin_password)"
  TF_VAR_cluster_admin_username="${TF_VAR_cluster_admin_username:-cluster-admin}"
  TF_VAR_aws_region="$(
    tf_output_raw aws_region
  )"
  if [[ -z "${TF_VAR_aws_region}" ]]; then
    TF_VAR_aws_region="$(grep -E '^\s*aws_region\s*=' "${WORK_DIR}/terraform.tfvars" | head -1 | sed -E 's/.*=\s*"([^"]+)".*/\1/' || true)"
  fi
  TF_VAR_aws_region="${TF_VAR_aws_region:-ap-south-1}"
  local domain
  domain="$(tf_output_raw cluster_domain)"
  if [[ -n "${domain}" ]]; then
    export TF_VAR_cluster_domain="${domain}"
  fi

  [[ -n "${TF_VAR_cluster_id}" ]] || die "empty cluster_id output — is the cluster in Terraform state?"
  [[ -n "${TF_VAR_cluster_api_url}" ]] || die "empty cluster_api_url output"
  ensure_cluster_admin_password
}

# --- main --------------------------------------------------------------------
require_cmd "$TF"
require_cmd python3
ensure_rhcs_token

if [[ "${SKIP_CLUSTER_APPLY:-0}" != "1" ]]; then
  log "Phase 1/2: ROSA HCP cluster stack (${WORK_DIR})"
  "$TF" -chdir="${WORK_DIR}" init -input=false
  tf_apply "${WORK_DIR}" "$@"
else
  log "Skipping cluster apply (SKIP_CLUSTER_APPLY=1)"
fi

if [[ "${SKIP_GITOPS_APPLY:-0}" == "1" ]]; then
  log "Skipping GitOps apply (SKIP_GITOPS_APPLY=1)"
  exit 0
fi

[[ -d "${GITOPS_DIR}" ]] || die "GitOps overlay not found: ${GITOPS_DIR}"

export_cluster_tf_vars
wait_for_cluster_api \
  "${TF_VAR_cluster_api_url}" \
  "${TF_VAR_cluster_admin_username}" \
  "${TF_VAR_cluster_admin_password}"

write_gitops_feature_tfvars

log "Phase 2/2: GitOps / RHOAI overlay (${GITOPS_DIR})"
"$TF" -chdir="${GITOPS_DIR}" init -input=false
# Credentials come from TF_VAR_*; feature flags from terraform.tfvars
tf_apply "${GITOPS_DIR}"

log "Full stack deploy complete (cluster + GitOps/RHOAI). Stacks remain separate; this script was the glue."
