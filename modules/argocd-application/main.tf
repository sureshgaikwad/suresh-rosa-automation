################################################################################
# ArgoCD Application Module
#
# Creates an ArgoCD Application resource in a reusable way.
# This module can be instantiated multiple times for different applications.
################################################################################

resource "null_resource" "argocd_application" {
  count = var.enabled ? 1 : 0

  provisioner "local-exec" {
    command = <<-EOT
      #!/bin/bash
      set -e

      export OC_USERNAME="${var.cluster_admin_username}"
      export OC_PASSWORD="${var.cluster_admin_password}"
      export OC_API_URL="${var.cluster_api_url}"
      source ${path.root}/scripts/oc-login.sh

      cat <<EOF | oc apply --kubeconfig=$KUBECONFIG -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ${var.application_name}
  namespace: ${var.argocd_namespace}
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: ${var.project}
  source:
    repoURL: ${var.repo_url}
    targetRevision: ${var.target_revision}
    path: ${var.path}
  destination:
    server: ${var.destination_server}
    namespace: ${var.destination_namespace}
  syncPolicy:
    automated:
      prune: ${var.auto_prune}
      selfHeal: ${var.self_heal}
      allowEmpty: false
    syncOptions:
      - CreateNamespace=${var.create_namespace}
      - RespectIgnoreDifferences=true
      - ApplyOutOfSyncOnly=true
    retry:
      limit: ${var.retry_limit}
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
EOF

      rm -f $KUBECONFIG
      echo "ArgoCD application '${var.application_name}' created"
    EOT
  }

  triggers = {
    cluster_id       = var.cluster_id
    application_name = var.application_name
    repo_url         = var.repo_url
    path             = var.path
  }
}
