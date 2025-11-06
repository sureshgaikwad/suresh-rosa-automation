# Validate and fix ServiceMesh Control Plane after OpenShift AI deployment
resource "null_resource" "validate_and_fix_smcp" {
  count      = var.deploy_openshift_ai && local.deploy_openshift_servicemesh && var.deploy_openshift_gitops ? 1 : 0
  depends_on = [null_resource.create_openshift_ai_application]

  provisioner "local-exec" {
    command = <<-EOT
      #!/bin/bash
      set -e
      
      echo "============================================================"
      echo "  Validating ServiceMeshControlPlane Health"
      echo "============================================================"
      
      # Login to cluster
      oc login --username="${module.rosa_cluster_hcp.cluster_admin_username}" --password="${module.rosa_cluster_hcp.cluster_admin_password}" "${module.rosa_cluster_hcp.cluster_api_url}" --insecure-skip-tls-verify
      
      # Wait for SMCP to be created by DataScienceCluster
      echo "Waiting for ServiceMeshControlPlane to be created..."
      for i in $(seq 1 60); do
        if oc get smcp data-science-smcp -n istio-system &>/dev/null; then
          echo "SMCP found"
          break
        fi
        if [ $i -eq 60 ]; then
          echo "ERROR: SMCP was not created by OpenShift AI"
          exit 1
        fi
        echo "Waiting for SMCP... (attempt $i/60)"
        sleep 10
      done
      
      # Check SMCP status
      echo "Checking SMCP status..."
      SMCP_READY=$(oc get smcp data-science-smcp -n istio-system -o jsonpath='{.status.annotations.readyComponentCount}' 2>/dev/null || echo "0")
      SMCP_STATUS=$(oc get smcp data-science-smcp -n istio-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
      
      echo "SMCP ready components: $SMCP_READY"
      echo "SMCP status: $SMCP_STATUS"
      
      # Check for conversion webhook errors in istio-operator logs
      echo "Checking for conversion webhook errors..."
      WEBHOOK_ERRORS=$(oc logs -n openshift-operators -l name=istio-operator --tail=50 2>/dev/null | grep -c "failed to convert" || echo "0")
      
      if [ "$WEBHOOK_ERRORS" -gt "5" ] || [ "$SMCP_STATUS" != "True" ]; then
        echo "⚠️  SMCP is in bad state or webhook errors detected. Recreating SMCP..."
        
        # Delete and let it recreate
        oc delete smcp data-science-smcp -n istio-system || true
        
        echo "Waiting for SMCP to be recreated..."
        sleep 30
        
        # Wait for SMCP to be recreated and become ready
        for i in $(seq 1 60); do
          if oc get smcp data-science-smcp -n istio-system &>/dev/null; then
            SMCP_READY=$(oc get smcp data-science-smcp -n istio-system -o jsonpath='{.status.annotations.readyComponentCount}' 2>/dev/null || echo "0")
            if [ "$SMCP_READY" = "5" ] || [ "$SMCP_READY" = "ComponentsReady" ]; then
              echo "✅ SMCP is now ready with $SMCP_READY components"
              break
            fi
          fi
          if [ $i -eq 60 ]; then
            echo "WARNING: SMCP did not become fully ready, but continuing..."
            break
          fi
          echo "Waiting for SMCP to be ready... (attempt $i/60)"
          sleep 10
        done
      else
        echo "✅ SMCP is healthy"
      fi
      
      # Wait for istio pods to be running
      echo "Waiting for Istio control plane pods..."
      for i in $(seq 1 30); do
        ISTIOD_PODS=$(oc get pods -n istio-system -l app=istiod --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l || echo "0")
        if [ "$ISTIOD_PODS" -gt "0" ]; then
          echo "✅ Istiod pod is running"
          break
        fi
        if [ $i -eq 30 ]; then
          echo "WARNING: Istiod pod not running yet, but continuing..."
          break
        fi
        echo "Waiting for istiod... (attempt $i/30)"
        sleep 10
      done
      
      # Validate and restart odh-model-controller if it's crash looping
      echo "Checking odh-model-controller health..."
      ODH_CONTROLLER_RESTARTS=$(oc get pods -n redhat-ods-applications -l control-plane=odh-model-controller -o jsonpath='{.items[0].status.containerStatuses[0].restartCount}' 2>/dev/null || echo "0")
      
      if [ "$ODH_CONTROLLER_RESTARTS" -gt "10" ]; then
        echo "⚠️  odh-model-controller has restarted $ODH_CONTROLLER_RESTARTS times. Restarting it..."
        oc delete pod -n redhat-ods-applications -l control-plane=odh-model-controller || true
        
        echo "Waiting for odh-model-controller to be ready..."
        sleep 30
        
        for i in $(seq 1 20); do
          if oc get pods -n redhat-ods-applications -l control-plane=odh-model-controller --field-selector=status.phase=Running 2>/dev/null | grep -q "Running"; then
            echo "✅ odh-model-controller is running"
            break
          fi
          if [ $i -eq 20 ]; then
            echo "WARNING: odh-model-controller not running yet, but continuing..."
            break
          fi
          echo "Waiting for odh-model-controller... (attempt $i/20)"
          sleep 10
        done
      else
        echo "✅ odh-model-controller is healthy"
      fi
      
      echo "============================================================"
      echo "  ServiceMesh validation and recovery complete"
      echo "============================================================"
    EOT
  }

  triggers = {
    cluster_id          = module.rosa_cluster_hcp.cluster_id
    admin_username      = module.rosa_cluster_hcp.cluster_admin_username
    admin_password      = module.rosa_cluster_hcp.cluster_admin_password
    api_url             = module.rosa_cluster_hcp.cluster_api_url
    deploy_openshift_ai = var.deploy_openshift_ai
  }
}

# AI Model Deployment via ArgoCD
resource "null_resource" "create_ai_model_application" {
  count      = var.deploy_ai_model && var.deploy_openshift_gitops ? 1 : 0
  depends_on = [
    null_resource.create_openshift_ai_application,
    null_resource.validate_and_fix_smcp
  ]

  provisioner "local-exec" {
    command = <<-EOT
      #!/bin/bash
      set -e
      echo "Starting AI Model application deployment..."
      
      # Login to cluster
      echo "Logging into OpenShift cluster..."
      if ! oc login --username="${module.rosa_cluster_hcp.cluster_admin_username}" --password="${module.rosa_cluster_hcp.cluster_admin_password}" "${module.rosa_cluster_hcp.cluster_api_url}" --insecure-skip-tls-verify; then
        echo "ERROR: Failed to login to OpenShift cluster"
        exit 1
      fi
      echo "Successfully logged into cluster"

      # Create AI Model Application
      echo "Proceeding to create AI Model application..."

      # Create AI Model Application
      echo "Creating AI Model ArgoCD application..."
      if ! oc apply -f - <<AI_MODEL_APP_EOF
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
AI_MODEL_APP_EOF
      then
        echo "ERROR: Failed to create AI Model ArgoCD application"
        exit 1
      fi

      echo "AI model application created successfully!"
    EOT
  }

  triggers = {
    cluster_id      = module.rosa_cluster_hcp.cluster_id
    admin_username  = module.rosa_cluster_hcp.cluster_admin_username
    admin_password  = module.rosa_cluster_hcp.cluster_admin_password
    api_url         = module.rosa_cluster_hcp.cluster_api_url
    gitops_repo_url = var.gitops_repo_url
    deploy_ai_model = var.deploy_ai_model
  }
}

# Create OpenShift AI Operator Application via ArgoCD
resource "null_resource" "create_openshift_ai_application" {
  count      = var.deploy_openshift_ai && var.deploy_openshift_gitops ? 1 : 0
  depends_on = [time_sleep.wait_for_argocd]

  provisioner "local-exec" {
    command = <<EOF
      # Login to cluster
      oc login --username="${module.rosa_cluster_hcp.cluster_admin_username}" --password="${module.rosa_cluster_hcp.cluster_admin_password}" "${module.rosa_cluster_hcp.cluster_api_url}" --insecure-skip-tls-verify

      # Create OpenShift AI Operator Application
      oc apply -f - <<OPENSHIFT_AI_APP_EOF
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
OPENSHIFT_AI_APP_EOF

      echo "OpenShift AI operator application created"
    EOF
  }

  triggers = {
    cluster_id          = module.rosa_cluster_hcp.cluster_id
    admin_username      = module.rosa_cluster_hcp.cluster_admin_username
    admin_password      = module.rosa_cluster_hcp.cluster_admin_password
    api_url             = module.rosa_cluster_hcp.cluster_api_url
    gitops_repo_url     = var.gitops_repo_url
    deploy_openshift_ai = var.deploy_openshift_ai
  }
}

# Create OpenShift Serverless Operator Application via ArgoCD
resource "null_resource" "create_openshift_serverless_application" {
  count      = local.deploy_openshift_serverless && var.deploy_openshift_gitops ? 1 : 0
  depends_on = [time_sleep.wait_for_argocd]

  provisioner "local-exec" {
    command = <<EOF
      # Login to cluster
      oc login --username="${module.rosa_cluster_hcp.cluster_admin_username}" --password="${module.rosa_cluster_hcp.cluster_admin_password}" "${module.rosa_cluster_hcp.cluster_api_url}" --insecure-skip-tls-verify

      # Create OpenShift Serverless Operator Application
      oc apply -f - <<OPENSHIFT_SERVERLESS_APP_EOF
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
OPENSHIFT_SERVERLESS_APP_EOF

      echo "OpenShift Serverless operator application created"
    EOF
  }

  triggers = {
    cluster_id                  = module.rosa_cluster_hcp.cluster_id
    admin_username              = module.rosa_cluster_hcp.cluster_admin_username
    admin_password              = module.rosa_cluster_hcp.cluster_admin_password
    api_url                     = module.rosa_cluster_hcp.cluster_api_url
    gitops_repo_url             = var.gitops_repo_url
    deploy_openshift_serverless = local.deploy_openshift_serverless
  }
}

# Create OpenShift Service Mesh Operator Application via ArgoCD
resource "null_resource" "create_openshift_servicemesh_application" {
  count      = local.deploy_openshift_servicemesh && var.deploy_openshift_gitops ? 1 : 0
  depends_on = [time_sleep.wait_for_argocd]

  provisioner "local-exec" {
    command = <<EOF
      # Login to cluster
      oc login --username="${module.rosa_cluster_hcp.cluster_admin_username}" --password="${module.rosa_cluster_hcp.cluster_admin_password}" "${module.rosa_cluster_hcp.cluster_api_url}" --insecure-skip-tls-verify

      # Create OpenShift Service Mesh Operator Application
      oc apply -f - <<OPENSHIFT_SERVICEMESH_APP_EOF
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
OPENSHIFT_SERVICEMESH_APP_EOF

      echo "OpenShift Service Mesh operator application created"

      # Wait for SMCP object to be created and ready
 #     echo "Waiting for ServiceMeshControlPlane to be created..."
 #     timeout 600 bash -c 'until oc get smcp data-science-smcp -n istio-system 2>/dev/null; do echo "Waiting for SMCP..."; sleep 10; done'

      # Apply authorino patch to SMCP
 #     echo "Patching ServiceMeshControlPlane with authorino configuration..."
 #     oc patch smcp data-science-smcp --type merge -n istio-system --patch-file ${path.module}/authorino.yml

 #     echo "ServiceMeshControlPlane patched with authorino configuration"
    EOF
  }

  triggers = {
    cluster_id                   = module.rosa_cluster_hcp.cluster_id
    admin_username               = module.rosa_cluster_hcp.cluster_admin_username
    admin_password               = module.rosa_cluster_hcp.cluster_admin_password
    api_url                      = module.rosa_cluster_hcp.cluster_api_url
    gitops_repo_url              = var.gitops_repo_url
    deploy_openshift_servicemesh = local.deploy_openshift_servicemesh
    authorino_patch              = fileexists("${path.module}/authorino.yml") ? file("${path.module}/authorino.yml") : ""
  }
}

# Create NodeFileDiscovery Operator Application via ArgoCD (GitOps Catalog)
resource "null_resource" "create_nfd_gitops_application" {
  count      = local.deploy_nfd_application && var.deploy_openshift_gitops ? 1 : 0
  depends_on = [time_sleep.wait_for_argocd]

  provisioner "local-exec" {
    command = <<-EOT
      #!/bin/bash
      set -e
      echo "Creating NodeFileDiscovery operator application via GitOps catalog..."
      
      # Login to cluster
      echo "Logging into OpenShift cluster..."
      if ! oc login --username="${module.rosa_cluster_hcp.cluster_admin_username}" --password="${module.rosa_cluster_hcp.cluster_admin_password}" "${module.rosa_cluster_hcp.cluster_api_url}" --insecure-skip-tls-verify; then
        echo "ERROR: Failed to login to OpenShift cluster"
        exit 1
      fi
      echo "Successfully logged into cluster"

      # Create NodeFileDiscovery Operator Application
      echo "Creating NodeFileDiscovery ArgoCD application..."
      if ! oc apply -f - <<NFD_GITOPS_APP_EOF
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
    repoURL: https://github.com/sureshgaikwad/gitops-catalog
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
NFD_GITOPS_APP_EOF
      then
        echo "ERROR: Failed to create NodeFileDiscovery GitOps ArgoCD application"
        exit 1
      fi

      echo "NodeFileDiscovery GitOps operator application created successfully!"
    EOT
  }

  triggers = {
    cluster_id             = module.rosa_cluster_hcp.cluster_id
    admin_username         = module.rosa_cluster_hcp.cluster_admin_username
    admin_password         = module.rosa_cluster_hcp.cluster_admin_password
    api_url                = module.rosa_cluster_hcp.cluster_api_url
    gitops_repo_url        = "https://github.com/sureshgaikwad/gitops-catalog"
    deploy_nfd_application = local.deploy_nfd_application
  }
}

# Create NVIDIA GPU Operator Application via ArgoCD (GitOps Catalog)
resource "null_resource" "create_nvidia_gpu_gitops_application" {
  count      = local.deploy_nvidia_gpu_operator_application && var.deploy_openshift_gitops ? 1 : 0
  depends_on = [time_sleep.wait_for_argocd]

  provisioner "local-exec" {
    command = <<-EOT
      #!/bin/bash
      set -e
      echo "Creating NVIDIA GPU operator application via GitOps catalog..."
      
      # Login to cluster
      echo "Logging into OpenShift cluster..."
      if ! oc login --username="${module.rosa_cluster_hcp.cluster_admin_username}" --password="${module.rosa_cluster_hcp.cluster_admin_password}" "${module.rosa_cluster_hcp.cluster_api_url}" --insecure-skip-tls-verify; then
        echo "ERROR: Failed to login to OpenShift cluster"
        exit 1
      fi
      echo "Successfully logged into cluster"

      # Create NVIDIA GPU Operator Application
      echo "Creating NVIDIA GPU ArgoCD application..."
      if ! oc apply -f - <<NVIDIA_GPU_GITOPS_APP_EOF
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
    repoURL: https://github.com/sureshgaikwad/gitops-catalog
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
NVIDIA_GPU_GITOPS_APP_EOF
      then
        echo "ERROR: Failed to create NVIDIA GPU GitOps ArgoCD application"
        exit 1
      fi

      echo "NVIDIA GPU GitOps operator application created successfully!"
    EOT
  }

  triggers = {
    cluster_id                             = module.rosa_cluster_hcp.cluster_id
    admin_username                         = module.rosa_cluster_hcp.cluster_admin_username
    admin_password                         = module.rosa_cluster_hcp.cluster_admin_password
    api_url                                = module.rosa_cluster_hcp.cluster_api_url
    gitops_repo_url                        = "https://github.com/sureshgaikwad/gitops-catalog"
    deploy_nvidia_gpu_operator_application = local.deploy_nvidia_gpu_operator_application
  }
}

# Create OpenShift Lightspeed Operator Application via ArgoCD (GitOps Catalog)
resource "null_resource" "create_openshift_lightspeed_application" {
  count = local.deploy_openshift_lightspeed && var.deploy_openshift_gitops ? 1 : 0
  depends_on = [
    time_sleep.wait_for_argocd,
    null_resource.create_ai_model_application # Wait for AI model to be deployed
  ]

  provisioner "local-exec" {
    command = <<EOT
#!/bin/bash
set -e

echo "Creating OpenShift Lightspeed operator application via GitOps catalog..."

# Login to cluster
echo "Logging into OpenShift cluster..."
if ! oc login --username="${module.rosa_cluster_hcp.cluster_admin_username}" --password="${module.rosa_cluster_hcp.cluster_admin_password}" "${module.rosa_cluster_hcp.cluster_api_url}" --insecure-skip-tls-verify; then
  echo "ERROR: Failed to login to OpenShift cluster"
  exit 1
fi
echo "Successfully logged into cluster"

# Create OpenShift Lightspeed ArgoCD application
echo "Creating OpenShift Lightspeed ArgoCD application..."
cat <<EOF | oc apply -f -
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
    repoURL: https://github.com/sureshgaikwad/gitops-catalog
    targetRevision: HEAD
    path: operators/openshift-lightspeed
  destination:
    server: https://kubernetes.default.svc
    namespace: openshift-lightspeed
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
  ignoreDifferences:
    - group: ols.openshift.io
      kind: OLSConfig
      name: cluster
EOF

# Wait for OpenShift Lightspeed operator to be ready
echo "Waiting for OpenShift Lightspeed operator to be ready..."
for i in $(seq 1 20); do
  if oc get csv -n openshift-lightspeed 2>/dev/null | grep -q "Succeeded"; then
    echo "OpenShift Lightspeed operator CSV is ready!"
    break
  fi
  if [ $i -eq 20 ]; then
    echo "ERROR: OpenShift Lightspeed operator CSV did not become ready in time"
    exit 1
  fi
  echo "Waiting for OpenShift Lightspeed operator CSV... (attempt $i/20)"
  sleep 15
done

# Wait for OpenShift Lightspeed CRDs to be available
echo "Waiting for OpenShift Lightspeed CRDs to be available..."
for i in $(seq 1 10); do
  if oc get crd olsconfigs.ols.openshift.io >/dev/null 2>&1; then
    echo "OLSConfig CRD is available!"
    break
  fi
  if [ $i -eq 10 ]; then
    echo "ERROR: OLSConfig CRD did not become available in time"
    exit 1
  fi
  echo "Waiting for OLSConfig CRD... (attempt $i/10)"
  sleep 10
done

# Additional wait to ensure operator controllers are fully initialized
echo "Waiting for operator controllers to fully initialize..."
sleep 30

# Use internal service URL for better performance and let operators handle authentication
echo "Configuring OpenShift Lightspeed with operator-managed authentication..."

# Dynamically discover the actual model service name and port
echo "Discovering deployed model service..."

# Try multiple discovery methods
MODEL_SERVICE_NAME=""

# Method 1: Look for predictor services
MODEL_SERVICE_NAME=$(oc get svc -n models -l component=predictor -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

# Method 2: If no predictor label, look for InferenceService-related services
if [ -z "$MODEL_SERVICE_NAME" ]; then
  MODEL_SERVICE_NAME=$(oc get svc -n models -o jsonpath='{.items[?(@.metadata.labels.serving\.kserve\.io/inferenceservice)].metadata.name}' 2>/dev/null | head -n1)
fi

# Method 3: Look for any service ending with -predictor
if [ -z "$MODEL_SERVICE_NAME" ]; then
  MODEL_SERVICE_NAME=$(oc get svc -n models --no-headers 2>/dev/null | grep -E "\-predictor\s" | head -n1 | awk '{print $1}' || echo "")
fi

if [ -z "$MODEL_SERVICE_NAME" ]; then
  echo "ERROR: No model predictor service found in models namespace"
  echo "Available services in models namespace:"
  oc get svc -n models 2>/dev/null || echo "No services found"
  exit 1
fi

# Get the service port (use port 8080 directly since that's what vLLM uses internally for headless services)
MODEL_PORT="8080"
DYNAMIC_MODEL_URL="http://$${MODEL_SERVICE_NAME}.models.svc.cluster.local:$${MODEL_PORT}/v1"
echo "Discovered model service: $MODEL_SERVICE_NAME"
echo "Using dynamic service URL: $DYNAMIC_MODEL_URL"

# Validate the service exists and is accessible
echo "Validating service accessibility..."
if ! oc get svc "$MODEL_SERVICE_NAME" -n models >/dev/null 2>&1; then
  echo "ERROR: Service $MODEL_SERVICE_NAME not found in models namespace"
  exit 1
fi

# Fetch the template from Git repository and process it
echo "Fetching and processing GitOps templates..."
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

# Clone the specific directory from Git repo
git clone --depth 1 --filter=blob:none --sparse https://github.com/sureshgaikwad/gitops-catalog.git
cd gitops-catalog
git sparse-checkout set operators/openshift-lightspeed

# Process OpenShift Lightspeed templates with minimal configuration
echo "Processing OpenShift Lightspeed templates..."
if [ -d "operators/openshift-lightspeed" ]; then
  cd operators/openshift-lightspeed
  
  # Process template files
  for template_file in *.template; do
    if [ -f "$template_file" ]; then
      output_file=$(basename "$template_file" .template).yaml
      echo "Processing $template_file -> $output_file"
      sed "s|{{DYNAMIC_MODEL_URL}}|$$DYNAMIC_MODEL_URL|g" "$template_file" > "$output_file"
    fi
  done
  
  echo "Applying OpenShift Lightspeed resources..."
  for yaml_file in *.yaml *.yml; do
    if [ -f "$yaml_file" ] && [ "$yaml_file" != "kustomization.yaml" ]; then
      echo "Applying $yaml_file..."
      
      # Special handling for OLSConfig - validate CRD is ready before applying
      if [[ "$yaml_file" == *"olsconfig"* ]]; then
        echo "Validating OLSConfig CRD availability before applying..."
        if ! oc get crd olsconfigs.ols.openshift.io >/dev/null 2>&1; then
          echo "ERROR: OLSConfig CRD is not available, cannot apply $yaml_file"
          continue
        fi
        echo "OLSConfig CRD confirmed available, proceeding with $yaml_file"
      fi
      
      # Apply the resource with retry logic
      for attempt in $(seq 1 3); do
        if oc apply -f "$yaml_file"; then
          echo "Successfully applied $yaml_file"
          break
        else
          echo "Failed to apply $yaml_file (attempt $attempt/3)"
          if [ $attempt -eq 3 ]; then
            echo "ERROR: Failed to apply $yaml_file after 3 attempts"
            exit 1
          fi
          sleep 5
        fi
      done
    fi
  done
  cd ../..
fi

# Let the operators handle authentication integration automatically
echo "OpenShift AI and Authorino operators will handle authentication automatically"

# Clean up temporary directory
cd /
rm -rf "$TEMP_DIR"

# Validate that OLSConfig was created successfully
echo "Validating OLSConfig deployment..."
for i in $(seq 1 10); do
  if oc get olsconfig cluster >/dev/null 2>&1; then
    echo "✓ OLSConfig 'cluster' created successfully"
    
    # Check if the configuration is using the correct URL
    CONFIGURED_URL=$$(oc get olsconfig cluster -o jsonpath='{.spec.llm.providers[0].url}' 2>/dev/null || echo "")
    if [[ "$CONFIGURED_URL" == *"$MODEL_SERVICE_NAME"* ]]; then
      echo "✓ OLSConfig is using the correct dynamic model URL: $CONFIGURED_URL"
    else
      echo "⚠ Warning: OLSConfig URL ($CONFIGURED_URL) doesn't match expected service ($MODEL_SERVICE_NAME)"
    fi
    break
  fi
  if [ $i -eq 10 ]; then
    echo "✗ Warning: OLSConfig 'cluster' was not found after deployment"
  fi
  echo "Waiting for OLSConfig to be created... (attempt $i/10)"
  sleep 5
done

echo "OpenShift Lightspeed deployment completed!"
echo "Model URL configured as: $DYNAMIC_MODEL_URL"
echo "Authentication will be handled automatically by OpenShift AI and Authorino operators"
EOT
  }

  triggers = {
    cluster_id                  = module.rosa_cluster_hcp.cluster_id
    admin_username              = module.rosa_cluster_hcp.cluster_admin_username
    admin_password              = module.rosa_cluster_hcp.cluster_admin_password
    api_url                     = module.rosa_cluster_hcp.cluster_api_url
    gitops_repo_url             = "https://github.com/sureshgaikwad/gitops-catalog"
    deploy_openshift_lightspeed = local.deploy_openshift_lightspeed
    ai_model_dependency         = try(null_resource.create_ai_model_application[0].id, "")
  }
}

# Create Authorino Operator Application via ArgoCD (GitOps Catalog)
resource "null_resource" "create_authorino_operator_application" {
  count = var.deploy_authorino_operator && var.deploy_openshift_gitops ? 1 : 0
  depends_on = [
    time_sleep.wait_for_argocd
  ]

  provisioner "local-exec" {
    command = <<EOT
#!/bin/bash
set -e

echo "Creating Authorino operator application via GitOps catalog..."

# Login to cluster
echo "Logging into OpenShift cluster..."
if ! oc login --username="${module.rosa_cluster_hcp.cluster_admin_username}" --password="${module.rosa_cluster_hcp.cluster_admin_password}" "${module.rosa_cluster_hcp.cluster_api_url}" --insecure-skip-tls-verify; then
  echo "ERROR: Failed to login to OpenShift cluster"
  exit 1
fi
echo "Successfully logged into cluster"

# Create Authorino ArgoCD application
echo "Creating Authorino ArgoCD application..."
cat <<EOF | oc apply -f -
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
    repoURL: https://github.com/sureshgaikwad/gitops-catalog
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

# Wait for Authorino operator to be ready
echo "Waiting for Authorino operator to be ready..."
for i in $(seq 1 20); do
  if oc get csv -n authorino-operator 2>/dev/null | grep -q "Succeeded"; then
    echo "Authorino operator is ready!"
    break
  fi
  if [ $i -eq 20 ]; then
    echo "ERROR: Authorino operator did not become ready in time"
    exit 1
  fi
  echo "Waiting for Authorino operator... (attempt $i/20)"
  sleep 15
done

echo "Authorino operator application created successfully!"
EOT
  }

  triggers = {
    cluster_id                = module.rosa_cluster_hcp.cluster_id
    admin_username            = module.rosa_cluster_hcp.cluster_admin_username
    admin_password            = module.rosa_cluster_hcp.cluster_admin_password
    api_url                   = module.rosa_cluster_hcp.cluster_api_url
    gitops_repo_url           = "https://github.com/sureshgaikwad/gitops-catalog"
    deploy_authorino_operator = var.deploy_authorino_operator
  }
}
