#!/bin/bash
################################################################################
# bootstrap-gitops.sh
#
# Bootstraps OpenShift GitOps (ArgoCD) on a ROSA HCP cluster using outputs
# from Terraform. Run this script AFTER 'terraform apply' completes.
#
# This script replaces the Terraform-managed GitOps modules (null_resource +
# local-exec) and is the recommended approach for private/zero-egress clusters
# where Terraform may not have direct network access to the cluster API.
#
# Usage:
#   ./scripts/bootstrap-gitops.sh                    # reads terraform output from repo root
#   ./scripts/bootstrap-gitops.sh --tf-dir /path     # reads from a different dir
#   ./scripts/bootstrap-gitops.sh --skip-apps        # install operator only
#
# Prerequisites:
#   - oc CLI installed and on PATH
#   - jq installed and on PATH
#   - Network access to the cluster API (run from bastion/VPN for private clusters)
#   - terraform apply completed successfully
################################################################################

set -euo pipefail

###############################################################################
# Configuration (overridable via environment variables)
###############################################################################
TERRAFORM_DIR="${TERRAFORM_DIR:-.}"
GITOPS_CHANNEL="${GITOPS_CHANNEL:-gitops-1.14}"
NODE_WAIT_TIMEOUT="${NODE_WAIT_TIMEOUT:-300}"
OPERATOR_WAIT_TIMEOUT="${OPERATOR_WAIT_TIMEOUT:-300}"
ARGOCD_WAIT_TIMEOUT="${ARGOCD_WAIT_TIMEOUT:-120}"
SKIP_APPS="${SKIP_APPS:-false}"

###############################################################################
# Parse arguments
###############################################################################
while [[ $# -gt 0 ]]; do
  case $1 in
    --tf-dir)     TERRAFORM_DIR="$2"; shift 2 ;;
    --skip-apps)  SKIP_APPS=true; shift ;;
    --channel)    GITOPS_CHANNEL="$2"; shift 2 ;;
    --help|-h)
      echo "Usage: $0 [--tf-dir DIR] [--skip-apps] [--channel CHANNEL]"
      exit 0
      ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

###############################################################################
# Helper functions
###############################################################################
log()  { echo "==> $*"; }
info() { echo "    $*"; }
warn() { echo "    WARNING: $*"; }
die()  { echo "    ERROR: $*" >&2; exit 1; }

wait_for() {
  local description="$1" timeout="$2" interval="${3:-10}"
  shift 3
  local cmd=("$@")
  local elapsed=0
  log "Waiting for $description (timeout: ${timeout}s)..."
  while [ $elapsed -lt "$timeout" ]; do
    if "${cmd[@]}" >/dev/null 2>&1; then
      info "$description is ready"
      return 0
    fi
    sleep "$interval"
    elapsed=$((elapsed + interval))
    info "Waiting... ($elapsed/${timeout}s)"
  done
  warn "Timeout waiting for $description"
  return 1
}

###############################################################################
# Read Terraform outputs
###############################################################################
log "Reading Terraform outputs from: $TERRAFORM_DIR"
TF_OUTPUT=$(cd "$TERRAFORM_DIR" && terraform output -json)

CLUSTER_API_URL=$(echo "$TF_OUTPUT" | jq -r '.cluster_api_url.value // empty')
CLUSTER_ADMIN_USER=$(echo "$TF_OUTPUT" | jq -r '.cluster_admin_username.value // empty')
CLUSTER_ADMIN_PASS=$(echo "$TF_OUTPUT" | jq -r '.cluster_admin_password.value // empty')
CLUSTER_ID=$(echo "$TF_OUTPUT" | jq -r '.cluster_id.value // empty')

[ -z "$CLUSTER_API_URL" ]   && die "cluster_api_url not found in terraform output"
[ -z "$CLUSTER_ADMIN_USER" ] && die "cluster_admin_username not found in terraform output"
[ -z "$CLUSTER_ADMIN_PASS" ] && die "cluster_admin_password not found in terraform output"

info "Cluster API: $CLUSTER_API_URL"
info "Cluster ID:  $CLUSTER_ID"

###############################################################################
# Login to cluster
###############################################################################
export KUBECONFIG=$(mktemp /tmp/rosa-kubeconfig-XXXXXX)
trap 'rm -f "$KUBECONFIG"' EXIT

log "Logging into cluster..."
if ! oc login --username="$CLUSTER_ADMIN_USER" \
              --password="$CLUSTER_ADMIN_PASS" \
              "$CLUSTER_API_URL" \
              --insecure-skip-tls-verify \
              --kubeconfig="$KUBECONFIG"; then
  die "Failed to login. For private/zero-egress clusters, run from a network that can reach the cluster API."
fi

###############################################################################
# Wait for cluster nodes
###############################################################################
log "Waiting for at least one node to be Ready..."
elapsed=0
while [ $elapsed -lt "$NODE_WAIT_TIMEOUT" ]; do
  ready_nodes=$(oc --kubeconfig="$KUBECONFIG" get nodes --no-headers 2>/dev/null | grep -c " Ready " || echo "0")
  if [ "$ready_nodes" -gt 0 ]; then
    info "$ready_nodes node(s) ready"
    break
  fi
  sleep 30
  elapsed=$((elapsed + 30))
  info "Waiting for nodes... ($elapsed/${NODE_WAIT_TIMEOUT}s)"
done

###############################################################################
# Wait for marketplace
###############################################################################
wait_for "OperatorHub marketplace" 120 15 \
  oc --kubeconfig="$KUBECONFIG" get packagemanifest openshift-gitops-operator || true

###############################################################################
# Install GitOps operator
###############################################################################
log "Installing OpenShift GitOps operator (channel: $GITOPS_CHANNEL)..."

cat <<EOF | oc --kubeconfig="$KUBECONFIG" apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-gitops
  labels:
    openshift.io/cluster-monitoring: "true"
EOF

cat <<EOF | oc --kubeconfig="$KUBECONFIG" apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-gitops-operator-group
  namespace: openshift-gitops
spec: {}
EOF

cat <<EOF | oc --kubeconfig="$KUBECONFIG" apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-gitops-operator
  namespace: openshift-gitops
spec:
  channel: ${GITOPS_CHANNEL}
  installPlanApproval: Automatic
  name: openshift-gitops-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

info "Operator subscription created"

###############################################################################
# Wait for operator to be ready
###############################################################################
log "Waiting for GitOps operator to install..."
elapsed=0
while [ $elapsed -lt "$OPERATOR_WAIT_TIMEOUT" ]; do
  csv=$(oc --kubeconfig="$KUBECONFIG" get csv -n openshift-gitops -o jsonpath='{.items[?(@.spec.displayName=="Red Hat OpenShift GitOps")].status.phase}' 2>/dev/null || echo "")
  if [ "$csv" = "Succeeded" ]; then
    info "GitOps operator installed successfully"
    break
  fi
  sleep 15
  elapsed=$((elapsed + 15))
  info "Operator status: ${csv:-Pending} ($elapsed/${OPERATOR_WAIT_TIMEOUT}s)"
done

###############################################################################
# Create ArgoCD instance
###############################################################################
log "Creating ArgoCD instance..."

cat <<EOF | oc --kubeconfig="$KUBECONFIG" apply -f -
apiVersion: argoproj.io/v1alpha1
kind: ArgoCD
metadata:
  name: openshift-gitops
  namespace: openshift-gitops
spec:
  server:
    route:
      enabled: true
      tls:
        termination: reencrypt
  dex:
    openShiftOAuth: true
    resources:
      limits:
        cpu: 500m
        memory: 256Mi
      requests:
        cpu: 250m
        memory: 128Mi
  rbac:
    defaultPolicy: role:admin
    policy: |
      p, role:admin, applications, *, */*, allow
      p, role:admin, certificates, *, *, allow
      p, role:admin, clusters, *, *, allow
      p, role:admin, repositories, *, *, allow
      g, system:cluster-admins, role:admin
    scopes: '[groups]'
  controller:
    processors: {}
    resources:
      limits:
        cpu: 2000m
        memory: 2048Mi
      requests:
        cpu: 250m
        memory: 1024Mi
  redis:
    resources:
      limits:
        cpu: 500m
        memory: 256Mi
      requests:
        cpu: 250m
        memory: 128Mi
  ha:
    enabled: false
EOF

info "ArgoCD instance created"

###############################################################################
# Create RBAC for ArgoCD application controller
###############################################################################
log "Configuring ArgoCD RBAC..."

cat <<EOF | oc --kubeconfig="$KUBECONFIG" apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: argocd-application-controller-cluster-role
rules:
- apiGroups: ["*"]
  resources: ["*"]
  verbs: ["*"]
- nonResourceURLs: ["*"]
  verbs: ["*"]
EOF

cat <<EOF | oc --kubeconfig="$KUBECONFIG" apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: argocd-application-controller-cluster-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: argocd-application-controller-cluster-role
subjects:
- kind: ServiceAccount
  name: openshift-gitops-argocd-application-controller
  namespace: openshift-gitops
EOF

info "RBAC configured"

###############################################################################
# Wait for ArgoCD to be ready
###############################################################################
log "Waiting for ArgoCD server to be ready..."
sleep 30
wait_for "ArgoCD server deployment" "$ARGOCD_WAIT_TIMEOUT" 10 \
  oc --kubeconfig="$KUBECONFIG" rollout status deployment/openshift-gitops-server -n openshift-gitops --timeout=10s || true

###############################################################################
# Create ArgoCD Applications (from terraform output)
###############################################################################
if [ "$SKIP_APPS" = "true" ]; then
  log "Skipping ArgoCD application creation (--skip-apps)"
else
  APPS_JSON=$(echo "$TF_OUTPUT" | jq -r '.argocd_applications_config.value // empty')

  if [ -z "$APPS_JSON" ] || [ "$APPS_JSON" = "{}" ] || [ "$APPS_JSON" = "null" ]; then
    log "No ArgoCD applications configured in terraform output"
  else
    APP_COUNT=$(echo "$APPS_JSON" | jq 'length')
    log "Creating $APP_COUNT ArgoCD application(s)..."

    echo "$APPS_JSON" | jq -r 'keys[]' | while read -r APP_NAME; do
      REPO_URL=$(echo "$APPS_JSON" | jq -r ".\"$APP_NAME\".repo_url")
      APP_PATH=$(echo "$APPS_JSON" | jq -r ".\"$APP_NAME\".path")
      NAMESPACE=$(echo "$APPS_JSON" | jq -r ".\"$APP_NAME\".namespace")
      CREATE_NS=$(echo "$APPS_JSON" | jq -r ".\"$APP_NAME\".create_namespace // true")

      info "Creating application: $APP_NAME (namespace: $NAMESPACE)"

      cat <<EOF | oc --kubeconfig="$KUBECONFIG" apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ${APP_NAME}
  namespace: openshift-gitops
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: ${REPO_URL}
    targetRevision: HEAD
    path: ${APP_PATH}
  destination:
    server: https://kubernetes.default.svc
    namespace: ${NAMESPACE}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      allowEmpty: false
    syncOptions:
      - CreateNamespace=${CREATE_NS}
      - RespectIgnoreDifferences=true
      - ApplyOutOfSyncOnly=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
EOF
    done
    info "All applications created"
  fi
fi

###############################################################################
# Summary
###############################################################################
echo ""
echo "============================================================"
echo "  GitOps Bootstrap Complete"
echo "============================================================"
echo "  Cluster API:  $CLUSTER_API_URL"
echo "  ArgoCD URL:   https://openshift-gitops-server-openshift-gitops.apps.$(oc --kubeconfig="$KUBECONFIG" get ingress.config.openshift.io/cluster -o jsonpath='{.spec.domain}' 2>/dev/null || echo '<cluster-domain>')"
echo "============================================================"
