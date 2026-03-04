#!/bin/bash
################################################################################
# oc-login.sh -- shared cluster login helper
#
# Source this script from local-exec provisioners to authenticate to the
# ROSA cluster. It sets KUBECONFIG and performs 'oc login'.
#
# Expected environment variables (set by caller before sourcing):
#   OC_USERNAME  - cluster admin username
#   OC_PASSWORD  - cluster admin password
#   OC_API_URL   - cluster API URL
#
# After sourcing, KUBECONFIG is exported and all subsequent 'oc' commands
# will use it automatically. The caller should 'rm -f "$KUBECONFIG"' on exit.
################################################################################

set -e
export KUBECONFIG="${KUBECONFIG:-/tmp/rosa-kubeconfig-$$}"

if ! oc login --username="$OC_USERNAME" \
              --password="$OC_PASSWORD" \
              "$OC_API_URL" \
              --insecure-skip-tls-verify \
              --kubeconfig="$KUBECONFIG"; then
  echo "ERROR: Failed to login to cluster API ($OC_API_URL)"
  echo "HINT: For private/zero-egress clusters, run from a network that can reach the cluster API (VPN/DirectConnect/bastion/SSM in the VPC)."
  exit 1
fi
