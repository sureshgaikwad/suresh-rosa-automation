# ============================================================================
# ArgoCD Operator Applications
# ============================================================================
# This file creates ArgoCD applications for deploying operators via GitOps

# ----------------------------------------------------------------------------
# AI Model Application
# ----------------------------------------------------------------------------
resource "null_resource" "create_ai_model_application" {
  count      = var.deploy_ai_model && local.deploy_openshift_gitops ? 1 : 0
  depends_on = [time_sleep.wait_for_argocd[0]]

  provisioner "local-exec" {
    command = <<-EOT
      #!/bin/bash
      set -e
      
      if ! oc login --username="${module.rosa_cluster_hcp.cluster_admin_username}" \
                    --password="${module.rosa_cluster_hcp.cluster_admin_password}" \
                    "${module.rosa_cluster_hcp.cluster_api_url}" \
                    --insecure-skip-tls-verify; then
        echo "ERROR: Failed to login to OpenShift cluster"
        exit 1
      fi

      if ! oc apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ai-model
  namespace: openshift-gitops
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: ${var.gitops_repo_url}
    targetRevision: HEAD
    path: ai-models/mistral
  destination:
    server: https://kubernetes.default.svc
    namespace: models
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      allowEmpty: false
    syncOptions:
      - CreateNamespace=true
      - RespectIgnoreDifferences=true
      - ApplyOutOfSyncOnly=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
EOF
      then
        echo "ERROR: Failed to create ArgoCD application"
        exit 1
      fi
    EOT
  }

  triggers = {
    cluster_id      = module.rosa_cluster_hcp.cluster_id
    gitops_repo_url = var.gitops_repo_url
    deploy_ai_model = var.deploy_ai_model
  }
}

# ----------------------------------------------------------------------------
# OpenShift AI Operator Application
# ----------------------------------------------------------------------------
resource "null_resource" "create_openshift_ai_application" {
  count      = var.deploy_openshift_ai && local.deploy_openshift_gitops ? 1 : 0
  depends_on = [time_sleep.wait_for_argocd[0]]

  provisioner "local-exec" {
    command = <<-EOT
      #!/bin/bash
      set -e
      
      if ! oc login --username="${module.rosa_cluster_hcp.cluster_admin_username}" \
                    --password="${module.rosa_cluster_hcp.cluster_admin_password}" \
                    "${module.rosa_cluster_hcp.cluster_api_url}" \
                    --insecure-skip-tls-verify; then
        echo "ERROR: Failed to login to OpenShift cluster"
        exit 1
      fi

      if ! oc apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: openshift-ai-operator
  namespace: openshift-gitops
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: ${var.gitops_repo_url}
    targetRevision: HEAD
    path: operators/openshift-ai
  destination:
    server: https://kubernetes.default.svc
    namespace: redhat-ods-operator
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      allowEmpty: false
    syncOptions:
      - CreateNamespace=true
      - RespectIgnoreDifferences=true
      - ApplyOutOfSyncOnly=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
EOF
      then
        echo "ERROR: Failed to create ArgoCD application"
        exit 1
      fi
    EOT
  }

  triggers = {
    cluster_id          = module.rosa_cluster_hcp.cluster_id
    gitops_repo_url     = var.gitops_repo_url
    deploy_openshift_ai = var.deploy_openshift_ai
  }
}

# ----------------------------------------------------------------------------
# OpenShift Serverless Operator Application
# ----------------------------------------------------------------------------
resource "null_resource" "create_openshift_serverless_application" {
  count      = local.deploy_openshift_serverless && local.deploy_openshift_gitops ? 1 : 0
  depends_on = [time_sleep.wait_for_argocd[0]]

  provisioner "local-exec" {
    command = <<-EOT
      #!/bin/bash
      set -e
      
      if ! oc login --username="${module.rosa_cluster_hcp.cluster_admin_username}" \
                    --password="${module.rosa_cluster_hcp.cluster_admin_password}" \
                    "${module.rosa_cluster_hcp.cluster_api_url}" \
                    --insecure-skip-tls-verify; then
        echo "ERROR: Failed to login to OpenShift cluster"
        exit 1
      fi

      if ! oc apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: openshift-serverless-operator
  namespace: openshift-gitops
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: ${var.gitops_repo_url}
    targetRevision: HEAD
    path: operators/openshift-serverless
  destination:
    server: https://kubernetes.default.svc
    namespace: openshift-serverless
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      allowEmpty: false
    syncOptions:
      - CreateNamespace=true
      - RespectIgnoreDifferences=true
      - ApplyOutOfSyncOnly=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
EOF
      then
        echo "ERROR: Failed to create ArgoCD application"
        exit 1
      fi
    EOT
  }

  triggers = {
    cluster_id                  = module.rosa_cluster_hcp.cluster_id
    gitops_repo_url             = var.gitops_repo_url
    deploy_openshift_serverless = local.deploy_openshift_serverless
  }
}

# ----------------------------------------------------------------------------
# OpenShift Service Mesh Operator Application
# ----------------------------------------------------------------------------
resource "null_resource" "create_openshift_servicemesh_application" {
  count      = local.deploy_openshift_servicemesh && local.deploy_openshift_gitops ? 1 : 0
  depends_on = [time_sleep.wait_for_argocd[0]]

  provisioner "local-exec" {
    command = <<-EOT
      #!/bin/bash
      set -e
      
      if ! oc login --username="${module.rosa_cluster_hcp.cluster_admin_username}" \
                    --password="${module.rosa_cluster_hcp.cluster_admin_password}" \
                    "${module.rosa_cluster_hcp.cluster_api_url}" \
                    --insecure-skip-tls-verify; then
        echo "ERROR: Failed to login to OpenShift cluster"
        exit 1
      fi

      if ! oc apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: openshift-servicemesh-operator
  namespace: openshift-gitops
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: ${var.gitops_repo_url}
    targetRevision: HEAD
    path: operators/openshift-servicemesh
  destination:
    server: https://kubernetes.default.svc
    namespace: istio-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      allowEmpty: false
    syncOptions:
      - CreateNamespace=true
      - RespectIgnoreDifferences=true
      - ApplyOutOfSyncOnly=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
EOF
      then
        echo "ERROR: Failed to create ArgoCD application"
        exit 1
      fi
    EOT
  }

  triggers = {
    cluster_id                   = module.rosa_cluster_hcp.cluster_id
    gitops_repo_url              = var.gitops_repo_url
    deploy_openshift_servicemesh = local.deploy_openshift_servicemesh
  }
}

# ----------------------------------------------------------------------------
# Node Feature Discovery (NFD) Operator Application
# ----------------------------------------------------------------------------
resource "null_resource" "create_nfd_gitops_application" {
  count      = local.deploy_nfd && local.deploy_openshift_gitops ? 1 : 0
  depends_on = [time_sleep.wait_for_argocd[0]]

  provisioner "local-exec" {
    command = <<-EOT
      #!/bin/bash
      set -e
      
      if ! oc login --username="${module.rosa_cluster_hcp.cluster_admin_username}" \
                    --password="${module.rosa_cluster_hcp.cluster_admin_password}" \
                    "${module.rosa_cluster_hcp.cluster_api_url}" \
                    --insecure-skip-tls-verify; then
        echo "ERROR: Failed to login to OpenShift cluster"
        exit 1
      fi

      if ! oc apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: nfd-gitops
  namespace: openshift-gitops
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: ${var.gitops_repo_url}
    targetRevision: HEAD
    path: operators/node-file-discovery-operator
  destination:
    server: https://kubernetes.default.svc
    namespace: openshift-nfd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      allowEmpty: false
    syncOptions:
      - CreateNamespace=true
      - RespectIgnoreDifferences=true
      - ApplyOutOfSyncOnly=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
EOF
      then
        echo "ERROR: Failed to create ArgoCD application"
        exit 1
      fi
    EOT
  }

  triggers = {
    cluster_id      = module.rosa_cluster_hcp.cluster_id
    gitops_repo_url = var.gitops_repo_url
    deploy_nfd      = local.deploy_nfd
  }
}

# ----------------------------------------------------------------------------
# NVIDIA GPU Operator Application
# ----------------------------------------------------------------------------
resource "null_resource" "create_nvidia_gpu_gitops_application" {
  count      = local.deploy_nvidia_gpu_operator && local.deploy_openshift_gitops ? 1 : 0
  depends_on = [time_sleep.wait_for_argocd[0]]

  provisioner "local-exec" {
    command = <<-EOT
      #!/bin/bash
      set -e
      
      if ! oc login --username="${module.rosa_cluster_hcp.cluster_admin_username}" \
                    --password="${module.rosa_cluster_hcp.cluster_admin_password}" \
                    "${module.rosa_cluster_hcp.cluster_api_url}" \
                    --insecure-skip-tls-verify; then
        echo "ERROR: Failed to login to OpenShift cluster"
        exit 1
      fi

      if ! oc apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: nvidia-gpu-operator-gitops
  namespace: openshift-gitops
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: ${var.gitops_repo_url}
    targetRevision: HEAD
    path: operators/nvidia-gpu-operator
  destination:
    server: https://kubernetes.default.svc
    namespace: nvidia-gpu-operator
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      allowEmpty: false
    syncOptions:
      - CreateNamespace=true
      - RespectIgnoreDifferences=true
      - ApplyOutOfSyncOnly=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
EOF
      then
        echo "ERROR: Failed to create ArgoCD application"
        exit 1
      fi
    EOT
  }

  triggers = {
    cluster_id                 = module.rosa_cluster_hcp.cluster_id
    gitops_repo_url            = var.gitops_repo_url
    deploy_nvidia_gpu_operator = local.deploy_nvidia_gpu_operator
  }
}

# ----------------------------------------------------------------------------
# OpenShift Lightspeed Operator Application
# ----------------------------------------------------------------------------
resource "null_resource" "create_openshift_lightspeed_application" {
  count      = local.deploy_openshift_lightspeed && local.deploy_openshift_gitops ? 1 : 0
  depends_on = [time_sleep.wait_for_argocd[0]]

  provisioner "local-exec" {
    command = <<-EOT
      #!/bin/bash
      set -e
      
      if ! oc login --username="${module.rosa_cluster_hcp.cluster_admin_username}" \
                    --password="${module.rosa_cluster_hcp.cluster_admin_password}" \
                    "${module.rosa_cluster_hcp.cluster_api_url}" \
                    --insecure-skip-tls-verify; then
        echo "ERROR: Failed to login to OpenShift cluster"
        exit 1
      fi

      if ! oc apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: openshift-lightspeed
  namespace: openshift-gitops
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: ${var.gitops_repo_url}
    targetRevision: HEAD
    path: operators/openshift-lightspeed
  destination:
    server: https://kubernetes.default.svc
    namespace: openshift-lightspeed
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - RespectIgnoreDifferences=true
      - ApplyOutOfSyncOnly=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
EOF
      then
        echo "ERROR: Failed to create ArgoCD application"
        exit 1
      fi
    EOT
  }

  triggers = {
    cluster_id                  = module.rosa_cluster_hcp.cluster_id
    gitops_repo_url             = var.gitops_repo_url
    deploy_openshift_lightspeed = local.deploy_openshift_lightspeed
  }
}

# ----------------------------------------------------------------------------
# Authorino Operator Application
# ----------------------------------------------------------------------------
resource "null_resource" "create_authorino_operator_application" {
  count      = var.deploy_authorino_operator && local.deploy_openshift_gitops ? 1 : 0
  depends_on = [time_sleep.wait_for_argocd[0]]

  provisioner "local-exec" {
    command = <<-EOT
      #!/bin/bash
      set -e
      
      if ! oc login --username="${module.rosa_cluster_hcp.cluster_admin_username}" \
                    --password="${module.rosa_cluster_hcp.cluster_admin_password}" \
                    "${module.rosa_cluster_hcp.cluster_api_url}" \
                    --insecure-skip-tls-verify; then
        echo "ERROR: Failed to login to OpenShift cluster"
        exit 1
      fi

      if ! oc apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: authorino-operator
  namespace: openshift-gitops
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: ${var.gitops_repo_url}
    targetRevision: HEAD
    path: operators/authorino-operator
  destination:
    server: https://kubernetes.default.svc
    namespace: authorino-operator
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      allowEmpty: false
    syncOptions:
      - CreateNamespace=true
      - RespectIgnoreDifferences=true
      - ApplyOutOfSyncOnly=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
EOF
      then
        echo "ERROR: Failed to create ArgoCD application"
        exit 1
      fi
    EOT
  }

  triggers = {
    cluster_id                = module.rosa_cluster_hcp.cluster_id
    gitops_repo_url           = var.gitops_repo_url
    deploy_authorino_operator = var.deploy_authorino_operator
  }
}

# ----------------------------------------------------------------------------
# Keycloak Operator Application
# ----------------------------------------------------------------------------
# Create Keycloak Operator Application via ArgoCD (GitOps Catalog)
resource "null_resource" "create_keycloak_application" {
  count = var.deploy_keycloak && local.deploy_openshift_gitops ? 1 : 0
  depends_on = [
    time_sleep.wait_for_argocd[0]
  ]

  provisioner "local-exec" {
    command = <<EOT
#!/bin/bash
set -e

echo "Creating Keycloak operator application via GitOps catalog..."

# Login to cluster
echo "Logging into OpenShift cluster..."
if ! oc login --username="${module.rosa_cluster_hcp.cluster_admin_username}" --password="${module.rosa_cluster_hcp.cluster_admin_password}" "${module.rosa_cluster_hcp.cluster_api_url}" --insecure-skip-tls-verify; then
  echo "ERROR: Failed to login to OpenShift cluster"
  exit 1
fi
echo "Successfully logged into cluster"

# Normalize repository URL (remove .git suffix if present for consistency)
REPO_URL="${replace(var.gitops_repo_url, ".git", "")}"
echo "Repository URL: $REPO_URL"
echo "Path: operators/keycloak/base"
echo ""
echo "Note: If sync status shows 'Unknown', check:"
echo "  1. Repository is accessible: $REPO_URL"
echo "  2. Path exists: operators/keycloak/base"
echo "  3. ArgoCD repository credentials are configured"
echo "  4. Check ArgoCD UI -> Settings -> Repositories for connection status"
echo ""

# Create Keycloak ArgoCD application
echo "Creating Keycloak ArgoCD application..."
cat <<EOF | oc apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: keycloak-operator
  namespace: openshift-gitops
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: ${replace(var.gitops_repo_url, ".git", "")}
    targetRevision: HEAD
    path: operators/keycloak/base
  destination:
    server: https://kubernetes.default.svc
    namespace: keycloak-operator
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      allowEmpty: false
    syncOptions:
      - CreateNamespace=true
      - RespectIgnoreDifferences=true
      - ApplyOutOfSyncOnly=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
EOF

echo "Keycloak operator application created successfully!"
echo ""
echo "Verifying application status..."
sleep 2
if oc get application keycloak-operator -n openshift-gitops &>/dev/null; then
  echo "✓ Application 'keycloak-operator' exists in openshift-gitops namespace"
  SYNC_STATUS=$(oc get application keycloak-operator -n openshift-gitops -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
  HEALTH_STATUS=$(oc get application keycloak-operator -n openshift-gitops -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
  echo "  Current sync status: $SYNC_STATUS"
  echo "  Current health status: $HEALTH_STATUS"
  
  if [ "$SYNC_STATUS" = "Unknown" ]; then
    echo ""
    echo "⚠ WARNING: Sync status is 'Unknown'"
    echo "This usually means ArgoCD cannot access the repository or the path doesn't exist."
    echo ""
    echo "Troubleshooting steps:"
    echo "  1. Check ArgoCD UI -> Settings -> Repositories"
    echo "     - Verify repository $REPO_URL is listed and connection status is 'Successful'"
    echo "  2. Verify the path exists in the repository:"
    echo "     - Check: $REPO_URL/tree/HEAD/operators/keycloak/base"
    echo "  3. If repository needs authentication, configure it in ArgoCD:"
    echo "     - ArgoCD UI -> Settings -> Repositories -> Connect Repo"
    echo "  4. Manually refresh the application in ArgoCD UI"
    echo ""
  fi
else
  echo "⚠ Warning: Could not verify application creation"
fi
EOT
  }

  triggers = {
    cluster_id      = module.rosa_cluster_hcp.cluster_id
    admin_username  = module.rosa_cluster_hcp.cluster_admin_username
    admin_password  = module.rosa_cluster_hcp.cluster_admin_password
    api_url         = module.rosa_cluster_hcp.cluster_api_url
    gitops_repo_url = var.gitops_repo_url
    deploy_keycloak = var.deploy_keycloak
  }
}

# ----------------------------------------------------------------------------
# Developer Hub Application
# ----------------------------------------------------------------------------
# Create Developer Hub Application via ArgoCD (GitOps Catalog)
# Note: Must wait for template processor to generate required config files
resource "null_resource" "create_developerhub_application" {
  count = var.deploy_developerhub && local.deploy_openshift_gitops ? 1 : 0
  depends_on = [
    time_sleep.wait_for_argocd[0],
    null_resource.create_keycloak_application,
    null_resource.process_gitops_templates # Wait for templates to be processed and pushed to Git
  ]

  provisioner "local-exec" {
    command = <<EOT
#!/bin/bash
set -e

echo "Creating Developer Hub application via GitOps catalog..."

# Login to cluster
echo "Logging into OpenShift cluster..."
if ! oc login --username="${module.rosa_cluster_hcp.cluster_admin_username}" --password="${module.rosa_cluster_hcp.cluster_admin_password}" "${module.rosa_cluster_hcp.cluster_api_url}" --insecure-skip-tls-verify; then
  echo "ERROR: Failed to login to OpenShift cluster"
  exit 1
fi
echo "Successfully logged into cluster"

# Verify that template processor has run (templates should be in Git)
echo "Verifying Developer Hub templates are processed..."
echo "Note: Templates should be processed by null_resource.process_gitops_templates"
echo "If resources are not syncing, check that auth-secret.yaml and app-config.yaml exist in Git repo at operators/developer-hub/base/"
echo ""
echo "Repository structure:"
echo "  Repository URL: ${var.gitops_repo_url}"
echo "  Path: operators/developer-hub/base (pointing directly to base directory)"
echo "  Expected files: auth-secret.yaml, app-config.yaml, and other YAML resources"
echo ""

# Create Developer Hub ArgoCD application
# Note: Path points directly to operators/developer-hub/base where all YAML resources are located
# This avoids kustomize dependency and uses plain YAML files directly
echo "Creating Developer Hub ArgoCD application..."
cat <<EOF | oc apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: developer-hub
  namespace: openshift-gitops
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: ${var.gitops_repo_url}
    targetRevision: HEAD
    path: operators/developer-hub/base
  destination:
    server: https://kubernetes.default.svc
    namespace: demo-project
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      allowEmpty: false
    syncOptions:
      - CreateNamespace=true
      - RespectIgnoreDifferences=true
      - ApplyOutOfSyncOnly=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
EOF

echo "Developer Hub application created successfully!"
EOT
  }

  triggers = {
    cluster_id          = module.rosa_cluster_hcp.cluster_id
    admin_username      = module.rosa_cluster_hcp.cluster_admin_username
    admin_password      = module.rosa_cluster_hcp.cluster_admin_password
    api_url             = module.rosa_cluster_hcp.cluster_api_url
    gitops_repo_url     = var.gitops_repo_url
    deploy_developerhub = var.deploy_developerhub
  }
}

# ----------------------------------------------------------------------------
# OpenShift DevSpaces Operator Application
# ----------------------------------------------------------------------------
resource "null_resource" "create_openshift_devspaces_application" {
  count      = var.deploy_openshift_devspaces && local.deploy_openshift_gitops ? 1 : 0
  depends_on = [time_sleep.wait_for_argocd[0]]

  provisioner "local-exec" {
    command = <<-EOT
      #!/bin/bash
      set -e
      
      if ! oc login --username="${module.rosa_cluster_hcp.cluster_admin_username}" \
                    --password="${module.rosa_cluster_hcp.cluster_admin_password}" \
                    "${module.rosa_cluster_hcp.cluster_api_url}" \
                    --insecure-skip-tls-verify; then
        echo "ERROR: Failed to login to OpenShift cluster"
        exit 1
      fi

      if ! oc apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: openshift-devspaces-operator
  namespace: openshift-gitops
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: ${var.gitops_repo_url}
    targetRevision: HEAD
    path: operators/openshift-devspaces
  destination:
    server: https://kubernetes.default.svc
    namespace: openshift-devspaces
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      allowEmpty: false
    syncOptions:
      - CreateNamespace=true
      - RespectIgnoreDifferences=true
      - ApplyOutOfSyncOnly=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
EOF
      then
        echo "ERROR: Failed to create ArgoCD application"
        exit 1
      fi
    EOT
  }

  triggers = {
    cluster_id                 = module.rosa_cluster_hcp.cluster_id
    gitops_repo_url            = var.gitops_repo_url
    deploy_openshift_devspaces = var.deploy_openshift_devspaces
  }
}

# ----------------------------------------------------------------------------
# OpenShift Virtualization Operator Application
# ----------------------------------------------------------------------------
resource "null_resource" "create_openshift_virtualization_application" {
  count      = var.deploy_openshift_virtualization && local.deploy_openshift_gitops ? 1 : 0
  depends_on = [time_sleep.wait_for_argocd[0]]

  provisioner "local-exec" {
    command = <<-EOT
      #!/bin/bash
      set -e
      
      if ! oc login --username="${module.rosa_cluster_hcp.cluster_admin_username}" \
                    --password="${module.rosa_cluster_hcp.cluster_admin_password}" \
                    "${module.rosa_cluster_hcp.cluster_api_url}" \
                    --insecure-skip-tls-verify; then
        echo "ERROR: Failed to login to OpenShift cluster"
        exit 1
      fi

      if ! oc apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: openshift-virtualization-operator
  namespace: openshift-gitops
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: ${var.gitops_repo_url}
    targetRevision: HEAD
    path: operators/openshift-virtualization
  destination:
    server: https://kubernetes.default.svc
    namespace: openshift-cnv
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      allowEmpty: false
    syncOptions:
      - CreateNamespace=true
      - RespectIgnoreDifferences=true
      - ApplyOutOfSyncOnly=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
EOF
      then
        echo "ERROR: Failed to create ArgoCD application"
        exit 1
      fi
    EOT
  }

  triggers = {
    cluster_id                      = module.rosa_cluster_hcp.cluster_id
    gitops_repo_url                 = var.gitops_repo_url
    deploy_openshift_virtualization = var.deploy_openshift_virtualization
  }
}

# ----------------------------------------------------------------------------
# Web Terminal Operator Application
# ----------------------------------------------------------------------------
resource "null_resource" "create_web_terminal_application" {
  count      = var.deploy_web_terminal && local.deploy_openshift_gitops ? 1 : 0
  depends_on = [time_sleep.wait_for_argocd[0]]

  provisioner "local-exec" {
    command = <<-EOT
      #!/bin/bash
      set -e
      
      if ! oc login --username="${module.rosa_cluster_hcp.cluster_admin_username}" \
                    --password="${module.rosa_cluster_hcp.cluster_admin_password}" \
                    "${module.rosa_cluster_hcp.cluster_api_url}" \
                    --insecure-skip-tls-verify; then
        echo "ERROR: Failed to login to OpenShift cluster"
        exit 1
      fi

      if ! oc apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: web-terminal-operator
  namespace: openshift-gitops
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: ${var.gitops_repo_url}
    targetRevision: HEAD
    path: operators/web-terminal
  destination:
    server: https://kubernetes.default.svc
    namespace: openshift-web-terminal
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      allowEmpty: false
    syncOptions:
      - CreateNamespace=true
      - RespectIgnoreDifferences=true
      - ApplyOutOfSyncOnly=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
EOF
      then
        echo "ERROR: Failed to create ArgoCD application"
        exit 1
      fi
    EOT
  }

  triggers = {
    cluster_id         = module.rosa_cluster_hcp.cluster_id
    gitops_repo_url    = var.gitops_repo_url
    deploy_web_terminal = var.deploy_web_terminal
  }
}

# ----------------------------------------------------------------------------
# Advanced Cluster Management (ACM) Operator Application
# ----------------------------------------------------------------------------
resource "null_resource" "create_advance_cluster_management_application" {
  count      = var.deploy_advance_cluster_management && local.deploy_openshift_gitops ? 1 : 0
  depends_on = [time_sleep.wait_for_argocd[0]]

  provisioner "local-exec" {
    command = <<-EOT
      #!/bin/bash
      set -e
      
      if ! oc login --username="${module.rosa_cluster_hcp.cluster_admin_username}" \
                    --password="${module.rosa_cluster_hcp.cluster_admin_password}" \
                    "${module.rosa_cluster_hcp.cluster_api_url}" \
                    --insecure-skip-tls-verify; then
        echo "ERROR: Failed to login to OpenShift cluster"
        exit 1
      fi

      if ! oc apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: advance-cluster-management-operator
  namespace: openshift-gitops
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: ${var.gitops_repo_url}
    targetRevision: HEAD
    path: operators/advance-cluster-management
  destination:
    server: https://kubernetes.default.svc
    namespace: open-cluster-management
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      allowEmpty: false
    syncOptions:
      - CreateNamespace=true
      - RespectIgnoreDifferences=true
      - ApplyOutOfSyncOnly=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
EOF
      then
        echo "ERROR: Failed to create ArgoCD application"
        exit 1
      fi
    EOT
  }

  triggers = {
    cluster_id                        = module.rosa_cluster_hcp.cluster_id
    gitops_repo_url                   = var.gitops_repo_url
    deploy_advance_cluster_management = var.deploy_advance_cluster_management
  }
}
