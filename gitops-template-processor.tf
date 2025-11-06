# Process GitOps templates and push to Git repository
# This resource runs AFTER cluster is deployed and ArgoCD is installed
# but BEFORE ArgoCD applications are created

resource "null_resource" "process_gitops_templates" {
  count = (var.deploy_keycloak || var.deploy_developerhub) && var.deploy_openshift_gitops ? 1 : 0

  # Must run after ArgoCD is ready but before creating applications
  depends_on = [
    time_sleep.wait_for_argocd
  ]

  provisioner "local-exec" {
    command = <<-EOT
      #!/bin/bash
      set -e
      
      # Set kubeconfig path
      export KUBECONFIG=/tmp/rosa-kubeconfig-$$
      
      echo "============================================================"
      echo "Processing GitOps Templates"
      echo "============================================================"
      echo ""
      
      # Login to cluster using Terraform outputs
      echo "1. Logging into cluster..."
      oc login \
        --username="${module.rosa_cluster_hcp.cluster_admin_username}" \
        --password="${module.rosa_cluster_hcp.cluster_admin_password}" \
        "${module.rosa_cluster_hcp.cluster_api_url}" \
        --insecure-skip-tls-verify \
        --kubeconfig=$KUBECONFIG
      
      # Get cluster domain dynamically
      echo ""
      echo "2. Detecting cluster domain..."
      CLUSTER_DOMAIN=$(oc --kubeconfig=$KUBECONFIG get ingress.config.openshift.io/cluster -o jsonpath='{.spec.domain}')
      echo "   Domain: $CLUSTER_DOMAIN"
      
      # Generate secrets
      echo ""
      echo "3. Generating secrets..."
      OIDC_CLIENT_SECRET=$(openssl rand -base64 32 | tr -d '\n')
      SESSION_SECRET=$(openssl rand -base64 32 | tr -d '\n')
      echo "   + OIDC client secret"
      echo "   + Session secret"
      
      # Generate ArgoCD token
      echo ""
      echo "4. Generating ArgoCD service account token..."
      ARGOCD_TOKEN=$(oc --kubeconfig=$KUBECONFIG create token openshift-gitops-argocd-server \
        -n openshift-gitops --duration=87600h 2>/dev/null || echo "PLACEHOLDER")
      
      if [ "$ARGOCD_TOKEN" = "PLACEHOLDER" ]; then
        echo "   WARNING: Could not generate token, will retry after deployment"
      else
        echo "   + Token generated"
      fi
      
      # Clone Git repository
      echo ""
      echo "5.  Cloning GitOps repository..."
      WORK_DIR=$(mktemp -d)
      cd "$WORK_DIR"
      git clone ${var.gitops_repo_url} gitops-catalog
      cd gitops-catalog
      
      # Configure Git
      git config user.name "Terraform Automation"
      git config user.email "terraform@automation.local"
      
      # Note: OAuth client is now created by Kubernetes Job in keycloak-client.yaml after Keycloak is deployed
      # This ensures Keycloak exists before trying to create the client
      
      # Process Keycloak templates (generate keycloak-client.yaml with Job)
      if [ "${var.deploy_keycloak}" = "true" ]; then
        echo ""
        echo "6.  Processing Keycloak templates..."
        cd operators/keycloak/base
        
        if [ -f "keycloak-client.yaml.template" ]; then
          sed -e "s|{{CLUSTER_DOMAIN}}|$CLUSTER_DOMAIN|g" \
              -e "s|{{OIDC_CLIENT_SECRET}}|$OIDC_CLIENT_SECRET|g" \
              keycloak-client.yaml.template > keycloak-client.yaml
          echo "   + keycloak-client.yaml generated (includes Job to create OAuth client)"
        fi
        
        cd ../../..
      fi
      
      # Process Developer Hub templates
      if [ "${var.deploy_developerhub}" = "true" ]; then
        echo ""
        echo "7.  Processing Developer Hub templates..."
        cd operators/developer-hub/base
        
        if [ -f "auth-secret.yaml.template" ]; then
          sed -e "s|{{CLUSTER_DOMAIN}}|$CLUSTER_DOMAIN|g" \
              -e "s|{{OIDC_CLIENT_SECRET}}|$OIDC_CLIENT_SECRET|g" \
              -e "s|{{SESSION_SECRET}}|$SESSION_SECRET|g" \
              -e "s|{{ARGOCD_TOKEN}}|$ARGOCD_TOKEN|g" \
              auth-secret.yaml.template > auth-secret.yaml
          echo "   + auth-secret.yaml generated"
        else
          echo "   ERROR: auth-secret.yaml.template not found!"
          exit 1
        fi
        
        if [ -f "app-config.yaml.template" ]; then
          sed "s|{{CLUSTER_DOMAIN}}|$CLUSTER_DOMAIN|g" \
              app-config.yaml.template > app-config.yaml
          echo "   + app-config.yaml generated"
        else
          echo "   ERROR: app-config.yaml.template not found!"
          exit 1
        fi
        
        cd ../../..
      fi
      
      # Commit and push to Git
      echo ""
      echo "8.  Committing and pushing to Git..."
      git add -f operators/keycloak/base/keycloak-client.yaml 2>/dev/null || true
      git add -f operators/developer-hub/base/auth-secret.yaml 2>/dev/null || true
      git add -f operators/developer-hub/base/app-config.yaml 2>/dev/null || true
      
      if git diff --staged --quiet; then
        echo "   INFO:  No changes to commit (files already exist)"
      else
        git commit -m "Generate cluster-specific configurations

Cluster: ${module.rosa_cluster_hcp.cluster_id}
Domain: $CLUSTER_DOMAIN
Generated by: Terraform
Timestamp: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

Files generated:
- operators/keycloak/base/keycloak-client.yaml
- operators/developer-hub/base/auth-secret.yaml
- operators/developer-hub/base/app-config.yaml
"
        
        # Push with retry logic
        MAX_RETRIES=3
        RETRY=0
        while [ $RETRY -lt $MAX_RETRIES ]; do
          if git push; then
            echo "   + Pushed to Git successfully"
            break
          else
            RETRY=$((RETRY + 1))
            if [ $RETRY -lt $MAX_RETRIES ]; then
              echo "   WARNING: Push failed, retrying ($RETRY/$MAX_RETRIES)..."
              sleep 5
            else
              echo "   ERROR: Failed to push after $MAX_RETRIES attempts"
              echo ""
              echo "ERROR: Could not push to Git repository."
              echo "This may be due to:"
              echo "  - Git credentials not configured"
              echo "  - Network issues"
              echo "  - Repository permissions"
              echo ""
              echo "Manual fix: Run /tmp/fix-argocd-sync.sh after terraform completes"
              exit 1
            fi
          fi
        done
      fi
      
      # Cleanup
      cd /
      rm -rf "$WORK_DIR"
      rm -f $KUBECONFIG
      
      # Save secrets for reference
      mkdir -p /tmp/devhub-secrets
      echo "$OIDC_CLIENT_SECRET" > /tmp/devhub-secrets/oidc-client-secret.txt
      echo "$SESSION_SECRET" > /tmp/devhub-secrets/session-secret.txt
      echo "$ARGOCD_TOKEN" > /tmp/devhub-secrets/argocd-token.txt
      
      echo ""
      echo "════════════════════════════════════════════════════════════"
      echo "✅ Template Processing Complete!"
      echo "════════════════════════════════════════════════════════════"
      echo ""
      echo "Generated configurations for:"
      echo "  Cluster Domain: $CLUSTER_DOMAIN"
      echo "  Repository: ${var.gitops_repo_url}"
      echo ""
      echo "Secrets saved to: /tmp/devhub-secrets/"
      echo ""
      echo "ArgoCD applications will now sync from Git repository."
      echo ""
    EOT

    interpreter = ["bash", "-c"]
  }

  # Track changes to trigger re-processing
  triggers = {
    cluster_id          = module.rosa_cluster_hcp.cluster_id
    cluster_api_url     = module.rosa_cluster_hcp.cluster_api_url
    admin_username      = module.rosa_cluster_hcp.cluster_admin_username
    gitops_repo_url     = var.gitops_repo_url
    deploy_keycloak     = var.deploy_keycloak
    deploy_developerhub = var.deploy_developerhub
    # Force re-run if needed by changing this timestamp
    timestamp = timestamp()
  }
}

# Output the status of template processing
output "gitops_templates_processed" {
  value       = var.deploy_keycloak || var.deploy_developerhub ? "Templates will be processed during apply" : "Template processing disabled"
  description = "Status of GitOps template processing"
}

output "gitops_secrets_location" {
  value       = var.deploy_keycloak || var.deploy_developerhub ? "/tmp/devhub-secrets/" : "N/A"
  description = "Location where generated secrets are saved for reference"
}

