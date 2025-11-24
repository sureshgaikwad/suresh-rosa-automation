# Wait for cluster to be ready before installing operators (reduced wait time)
resource "time_sleep" "wait_for_cluster" {
  count           = var.deploy_openshift_gitops ? 1 : 0
  depends_on      = [module.rosa_cluster_hcp]
  create_duration = "30s"
}

# Wait for cluster and nodes to be ready before installing GitOps operator
resource "null_resource" "wait_for_cluster_and_nodes" {
  count      = var.deploy_openshift_gitops ? 1 : 0
  depends_on = [time_sleep.wait_for_cluster]

  provisioner "local-exec" {
    command = <<-EOT
      #!/bin/bash
      set -e
      echo "Checking cluster and node readiness..."
      
      # Login to cluster
      oc login --username="${module.rosa_cluster_hcp.cluster_admin_username}" --password="${module.rosa_cluster_hcp.cluster_admin_password}" "${module.rosa_cluster_hcp.cluster_api_url}" --insecure-skip-tls-verify
      
      # Wait for at least 1 node to be ready (quick start for operators)
      echo "Waiting for at least 1 node to be ready (timeout: 5 minutes)..."
      wait_start=$(date +%s)
      wait_timeout=300
      
      # Start operators as soon as 1 node is ready
      MIN_READY_NODES=1
      
      while true; do
        current_time=$(date +%s)
        elapsed=$((current_time - wait_start))
        
        if [ $elapsed -ge $wait_timeout ]; then
          echo "WARNING: Timeout waiting for nodes after 5 minutes, but continuing..."
          break
        fi
        
        ready_nodes=$(oc get nodes --no-headers 2>/dev/null | grep -c " Ready " || echo "0")
        total_nodes=$(oc get nodes --no-headers 2>/dev/null | wc -l || echo "0")
        echo "Ready nodes: $ready_nodes / Total nodes: $total_nodes (elapsed: $${elapsed}s)"
        
        # Proceed as soon as we have at least 1 ready node
        if [ "$ready_nodes" -ge "$MIN_READY_NODES" ]; then
          echo "At least 1 node is ready! Starting operator deployment..."
          break
        fi
        
        echo "Waiting for at least 1 node to be ready... (checking again in 15 seconds)"
        sleep 15
      done
      
      # Wait for OpenShift marketplace to be available (reduced timeout)
      echo "Waiting for OpenShift marketplace to be ready..."
      wait_start=$(date +%s)
      wait_timeout=180
      
      while true; do
        current_time=$(date +%s)
        elapsed=$((current_time - wait_start))
        
        if [ $elapsed -ge $wait_timeout ]; then
          echo "WARNING: Timeout waiting for marketplace after 3 minutes, but continuing..."
          break
        fi
        
        if oc get packagemanifest openshift-gitops-operator >/dev/null 2>&1; then
          echo "OpenShift marketplace is ready!"
          break
        fi
        
        echo "Waiting for marketplace to be available... (elapsed: $${elapsed}s)"
        sleep 10
      done
      
      echo "Cluster and nodes are ready for GitOps installation!"
    EOT
  }

  triggers = {
    cluster_id     = module.rosa_cluster_hcp.cluster_id
    admin_username = module.rosa_cluster_hcp.cluster_admin_username
    admin_password = module.rosa_cluster_hcp.cluster_admin_password
    api_url        = module.rosa_cluster_hcp.cluster_api_url
  }
}

# Install GitOps operator using oc commands for reliability
resource "null_resource" "install_gitops_operator" {
  count      = var.deploy_openshift_gitops ? 1 : 0
  depends_on = [null_resource.wait_for_cluster_and_nodes]

  provisioner "local-exec" {
    command = <<EOF
      # Login to cluster
      oc login --username="${module.rosa_cluster_hcp.cluster_admin_username}" --password="${module.rosa_cluster_hcp.cluster_admin_password}" "${module.rosa_cluster_hcp.cluster_api_url}" --insecure-skip-tls-verify

      # Check if GitOps operator is already installed and ready
      echo "Checking if GitOps operator is already installed..."
      csv_name=$(oc get csv -n openshift-gitops 2>/dev/null | grep -i "openshift-gitops" | head -1 | awk '{print $1}' || echo "")
      
      if [ -z "$csv_name" ]; then
        csv_name=$(oc get subscription openshift-gitops-operator -n openshift-gitops -o jsonpath='{.status.currentCSV}' 2>/dev/null || echo "")
      fi
      
      if [ -n "$csv_name" ]; then
        csv_phase=$(oc get csv "$csv_name" -n openshift-gitops -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
        if [ "$csv_phase" = "Succeeded" ]; then
          echo "GitOps operator is already installed and ready (CSV: $csv_name). Skipping installation."
          exit 0
        fi
      fi

      # Create namespace
      oc apply -f - <<NAMESPACE_EOF
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-gitops
  labels:
    openshift.io/cluster-monitoring: "true"
NAMESPACE_EOF

      # Create OperatorGroup (cluster-wide for GitOps operator)
      oc apply -f - <<OPERATORGROUP_EOF
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-gitops-operator-group
  namespace: openshift-gitops
spec: {}
OPERATORGROUP_EOF

      # Create Subscription
      oc apply -f - <<SUBSCRIPTION_EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-gitops-operator
  namespace: openshift-gitops
spec:
  channel: gitops-1.14
  installPlanApproval: Automatic
  name: openshift-gitops-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
SUBSCRIPTION_EOF

      echo "GitOps operator subscription created, checking CSV status..."
      
      # Check for CSV immediately - if it's already Succeeded, proceed right away
      echo "Checking if GitOps operator CSV is already ready..."
      
      csv_ready=false
      
      # Try multiple methods to find the CSV
      csv_name=$(oc get csv -n openshift-gitops 2>/dev/null | grep -i "openshift-gitops" | head -1 | awk '{print $1}' || echo "")
      
      if [ -z "$csv_name" ]; then
        # Try finding by subscription
        csv_name=$(oc get subscription openshift-gitops-operator -n openshift-gitops -o jsonpath='{.status.currentCSV}' 2>/dev/null || echo "")
      fi
      
      if [ -n "$csv_name" ]; then
        # Get CSV phase/status
        csv_phase=$(oc get csv "$csv_name" -n openshift-gitops -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
        csv_conditions=$(oc get csv "$csv_name" -n openshift-gitops -o jsonpath='{.status.conditions[?(@.type=="Succeeded")].status}' 2>/dev/null || echo "")
        
        echo "Found CSV: $csv_name, Phase: $csv_phase, Succeeded: $csv_conditions"
        
        if [ "$csv_phase" = "Succeeded" ] || [ "$csv_conditions" = "True" ]; then
          echo "GitOps operator CSV is already ready (Succeeded)! Proceeding immediately."
          csv_ready=true
        fi
      fi
      
      # If CSV not found or not Succeeded, wait briefly (max 2 minutes)
      if [ "$csv_ready" = "false" ]; then
        echo "CSV not ready yet, waiting up to 2 minutes..."
        wait_start=$(date +%s)
        wait_timeout=120
        
        while true; do
          current_time=$(date +%s)
          elapsed=$((current_time - wait_start))
          
          if [ $elapsed -ge $wait_timeout ]; then
            echo "INFO: Timeout waiting for GitOps operator CSV after 2 minutes, but subscription exists. Continuing..."
            break
          fi
          
          # Check for CSV by name pattern
          csv_name=$(oc get csv -n openshift-gitops 2>/dev/null | grep -i "openshift-gitops" | head -1 | awk '{print $1}' || echo "")
          
          if [ -z "$csv_name" ]; then
            csv_name=$(oc get subscription openshift-gitops-operator -n openshift-gitops -o jsonpath='{.status.currentCSV}' 2>/dev/null || echo "")
          fi
          
          if [ -n "$csv_name" ]; then
            csv_phase=$(oc get csv "$csv_name" -n openshift-gitops -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
            csv_conditions=$(oc get csv "$csv_name" -n openshift-gitops -o jsonpath='{.status.conditions[?(@.type=="Succeeded")].status}' 2>/dev/null || echo "")
            
            echo "CSV: $csv_name, Phase: $csv_phase, Succeeded: $csv_conditions (elapsed: $${elapsed}s)"
            
            if [ "$csv_phase" = "Succeeded" ] || [ "$csv_conditions" = "True" ]; then
              echo "GitOps operator CSV is ready (Succeeded)!"
              break
            fi
            
            # Proceed if CSV exists and is installing (don't wait too long)
            if [ "$csv_phase" = "Installing" ] && [ $elapsed -ge 30 ]; then
              echo "CSV is installing, proceeding after 30 seconds..."
              break
            fi
          else
            echo "Waiting for GitOps operator CSV to appear... (elapsed: $${elapsed}s)"
          fi
          
          sleep 5
        done
      fi
      
      echo "GitOps operator installation check completed"
    EOF
  }

  # Cleanup on destroy
  provisioner "local-exec" {
    when    = destroy
    command = <<EOF
      #!/bin/bash
      set +e  # Don't exit on errors
      echo "Starting GitOps operator cleanup..."
      
      # Function to cleanup with maximum timeout of 3 minutes total
      cleanup_with_timeout() {
        # Login to cluster with timeout (using stored values)
        echo "Attempting to login to cluster..."
        timeout 30 oc login --username="${self.triggers.admin_username}" --password="${self.triggers.admin_password}" "${self.triggers.api_url}" --insecure-skip-tls-verify 2>/dev/null || {
          echo "Login failed or timed out, skipping cleanup..."
          return 0
        }

        # Delete subscription
        echo "Deleting GitOps operator subscription..."
        oc delete subscription openshift-gitops-operator -n openshift-gitops --ignore-not-found=true --timeout=20s 2>/dev/null || true

        # Delete operator group
        echo "Deleting GitOps operator group..."
        oc delete operatorgroup openshift-gitops-operator-group -n openshift-gitops --ignore-not-found=true --timeout=20s 2>/dev/null || true

        # Force delete namespace if it exists
        echo "Force deleting GitOps namespace..."
        oc patch namespace openshift-gitops -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
        oc delete namespace openshift-gitops --ignore-not-found=true --timeout=30s 2>/dev/null || true
        
        echo "GitOps operator cleanup completed"
      }

      # Run cleanup with overall timeout
      timeout 180 cleanup_with_timeout || {
        echo "Cleanup timed out after 3 minutes, but continuing..."
      }

      echo "Destroy provisioner finished"
      exit 0
    EOF
  }

  triggers = {
    cluster_id     = module.rosa_cluster_hcp.cluster_id
    admin_username = module.rosa_cluster_hcp.cluster_admin_username
    admin_password = module.rosa_cluster_hcp.cluster_admin_password
    api_url        = module.rosa_cluster_hcp.cluster_api_url
  }
}

# Wait for GitOps operator to be installed (minimal wait since we check CSV in install step)
# If operator is already installed, the script exits immediately, so this sleep is minimal
resource "time_sleep" "wait_for_gitops_operator" {
  count           = var.deploy_openshift_gitops ? 1 : 0
  depends_on      = [null_resource.install_gitops_operator]
  create_duration = "2s"
}
