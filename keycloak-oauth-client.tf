# Create Keycloak OAuth Client via Terraform
# This is done via Terraform (not GitOps) because:
# 1. OAuth client is cluster-specific with dynamic URLs
# 2. Client secret is generated at runtime
# 3. No need to push cluster-specific configs to Git
# 4. Simpler and cleaner for multi-cluster deployments

resource "null_resource" "create_keycloak_oauth_client" {
  count = var.deploy_keycloak && var.deploy_developerhub ? 1 : 0

  depends_on = [
    null_resource.process_gitops_templates
  ]

  triggers = {
    cluster_id         = module.rosa_cluster_hcp.cluster_id
    oidc_client_secret = random_password.oidc_client_secret[0].result
    cluster_domain     = data.external.cluster_domain[0].result.domain
  }

  provisioner "local-exec" {
    command = <<-EOT
      #!/bin/bash
      set -e
      
      export KUBECONFIG=/tmp/rosa-kubeconfig-$$
      
      echo "============================================================"
      echo "Creating Keycloak OAuth Client"
      echo "============================================================"
      echo ""
      
      # Login to cluster
      echo "1. Logging into cluster..."
      oc login \
        --username="${module.rosa_cluster_hcp.cluster_admin_username}" \
        --password="${module.rosa_cluster_hcp.cluster_admin_password}" \
        "${module.rosa_cluster_hcp.cluster_api_url}" \
        --insecure-skip-tls-verify \
        --kubeconfig=$KUBECONFIG
      
      # Wait for Keycloak to be ready
      echo ""
      echo "2. Waiting for Keycloak to be ready..."
      MAX_WAIT=300
      ELAPSED=0
      while [ $ELAPSED -lt $MAX_WAIT ]; do
        if oc --kubeconfig=$KUBECONFIG get route keycloak -n rhbk >/dev/null 2>&1; then
          KEYCLOAK_URL=$(oc --kubeconfig=$KUBECONFIG get route keycloak -n rhbk -o jsonpath='{.spec.host}')
          if curl -k -s "https://$KEYCLOAK_URL/realms/myrealm" 2>/dev/null | grep -q "myrealm"; then
            echo "   Keycloak is ready at: https://$KEYCLOAK_URL"
            break
          fi
        fi
        echo "   Waiting... ($ELAPSED/$MAX_WAIT seconds)"
        sleep 10
        ELAPSED=$((ELAPSED + 10))
      done
      
      if [ $ELAPSED -ge $MAX_WAIT ]; then
        echo "ERROR: Keycloak did not become ready within $MAX_WAIT seconds"
        exit 1
      fi
      
      # Get cluster domain
      CLUSTER_DOMAIN="${data.external.cluster_domain[0].result.domain}"
      OIDC_CLIENT_SECRET="${random_password.oidc_client_secret[0].result}"
      
      echo ""
      echo "3. Getting Keycloak admin credentials..."
      KEYCLOAK_URL=$(oc --kubeconfig=$KUBECONFIG get route keycloak -n rhbk -o jsonpath='{.spec.host}')
      ADMIN_PASS=$(oc --kubeconfig=$KUBECONFIG get secret sample-kc-initial-admin -n rhbk -o jsonpath='{.data.password}' | base64 -d)
      
      # Get admin token
      echo ""
      echo "4. Getting admin token..."
      TOKEN=$(curl -k -s -X POST "https://$KEYCLOAK_URL/realms/master/protocol/openid-connect/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "username=admin" \
        -d "password=$ADMIN_PASS" \
        -d "grant_type=password" \
        -d "client_id=admin-cli" | jq -r '.access_token')
      
      if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
        echo "ERROR: Failed to get admin token"
        exit 1
      fi
      
      # Check if client already exists
      echo ""
      echo "5. Checking if OAuth client exists..."
      EXISTING_CLIENT=$(curl -k -s -X GET "https://$KEYCLOAK_URL/admin/realms/myrealm/clients" \
        -H "Authorization: Bearer $TOKEN" | jq -r '.[] | select(.clientId=="myclient") | .id')
      
      if [ -z "$EXISTING_CLIENT" ]; then
        echo "   Creating new OAuth client 'myclient'..."
        HTTP_CODE=$(curl -k -s -w "%%{http_code}" -o /dev/null -X POST "https://$KEYCLOAK_URL/admin/realms/myrealm/clients" \
          -H "Authorization: Bearer $TOKEN" \
          -H "Content-Type: application/json" \
          -d "{
            \"clientId\": \"myclient\",
            \"name\": \"Developer Hub Client\",
            \"description\": \"OIDC client for Red Hat Developer Hub authentication\",
            \"enabled\": true,
            \"protocol\": \"openid-connect\",
            \"publicClient\": false,
            \"standardFlowEnabled\": true,
            \"implicitFlowEnabled\": false,
            \"directAccessGrantsEnabled\": false,
            \"secret\": \"$OIDC_CLIENT_SECRET\",
            \"redirectUris\": [
              \"https://backstage-developer-hub-demo-project.$CLUSTER_DOMAIN/*\",
              \"https://backstage-developer-hub-demo-project.$CLUSTER_DOMAIN/api/auth/oidc/handler/frame\"
            ],
            \"webOrigins\": [\"https://backstage-developer-hub-demo-project.$CLUSTER_DOMAIN\"],
            \"defaultClientScopes\": [\"openid\", \"email\", \"profile\", \"roles\", \"web-origins\"],
            \"optionalClientScopes\": [\"address\", \"phone\", \"offline_access\"]
          }")
        
        if [ "$HTTP_CODE" = "201" ]; then
          echo "   ✓ OAuth client created successfully"
        else
          echo "   ERROR: Failed to create client (HTTP $HTTP_CODE)"
          exit 1
        fi
      else
        echo "   OAuth client already exists, updating..."
        HTTP_CODE=$(curl -k -s -w "%%{http_code}" -o /dev/null -X PUT "https://$KEYCLOAK_URL/admin/realms/myrealm/clients/$EXISTING_CLIENT" \
          -H "Authorization: Bearer $TOKEN" \
          -H "Content-Type: application/json" \
          -d "{
            \"clientId\": \"myclient\",
            \"name\": \"Developer Hub Client\",
            \"description\": \"OIDC client for Red Hat Developer Hub authentication\",
            \"enabled\": true,
            \"protocol\": \"openid-connect\",
            \"publicClient\": false,
            \"standardFlowEnabled\": true,
            \"implicitFlowEnabled\": false,
            \"directAccessGrantsEnabled\": false,
            \"secret\": \"$OIDC_CLIENT_SECRET\",
            \"redirectUris\": [
              \"https://backstage-developer-hub-demo-project.$CLUSTER_DOMAIN/*\",
              \"https://backstage-developer-hub-demo-project.$CLUSTER_DOMAIN/api/auth/oidc/handler/frame\"
            ],
            \"webOrigins\": [\"https://backstage-developer-hub-demo-project.$CLUSTER_DOMAIN\"],
            \"defaultClientScopes\": [\"openid\", \"email\", \"profile\", \"roles\", \"web-origins\"],
            \"optionalClientScopes\": [\"address\", \"phone\", \"offline_access\"]
          }")
        
        if [ "$HTTP_CODE" = "204" ]; then
          echo "   ✓ OAuth client updated successfully"
        else
          echo "   ERROR: Failed to update client (HTTP $HTTP_CODE)"
          exit 1
        fi
      fi
      
      # Cleanup
      rm -f $KUBECONFIG
      
      echo ""
      echo "============================================================"
      echo "✓ OAuth Client Configuration Complete"
      echo "============================================================"
      echo ""
      echo "Client ID: myclient"
      echo "Cluster Domain: $CLUSTER_DOMAIN"
      echo "Redirect URIs:"
      echo "  - https://backstage-developer-hub-demo-project.$CLUSTER_DOMAIN/*"
      echo "  - https://backstage-developer-hub-demo-project.$CLUSTER_DOMAIN/api/auth/oidc/handler/frame"
      echo ""
    EOT
  }
}

# Generate OIDC client secret at runtime
resource "random_password" "oidc_client_secret" {
  count   = var.deploy_keycloak && var.deploy_developerhub ? 1 : 0
  length  = 32
  special = true
}

# Generate session secret at runtime
resource "random_password" "session_secret" {
  count   = var.deploy_developerhub ? 1 : 0
  length  = 32
  special = true
}

# Get cluster domain dynamically
data "external" "cluster_domain" {
  count = var.deploy_keycloak || var.deploy_developerhub ? 1 : 0
  
  depends_on = [null_resource.wait_for_cluster_and_nodes]
  
  program = ["bash", "-c", <<-EOT
    export KUBECONFIG=/tmp/rosa-kubeconfig-$$
    oc login --username="${module.rosa_cluster_hcp.cluster_admin_username}" \
             --password="${module.rosa_cluster_hcp.cluster_admin_password}" \
             "${module.rosa_cluster_hcp.cluster_api_url}" \
             --insecure-skip-tls-verify \
             --kubeconfig=$KUBECONFIG >/dev/null 2>&1
    DOMAIN=$(oc --kubeconfig=$KUBECONFIG get ingress.config.openshift.io/cluster -o jsonpath='{.spec.domain}')
    rm -f $KUBECONFIG
    echo "{\"domain\": \"$DOMAIN\"}"
  EOT
  ]
}

# Output the OIDC client secret for use in Developer Hub
output "oidc_client_secret" {
  value     = var.deploy_keycloak && var.deploy_developerhub ? random_password.oidc_client_secret[0].result : ""
  sensitive = true
}

