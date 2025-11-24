# Create Keycloak OAuth Client via Terraform
# This is done via Terraform (not GitOps) because:
# 1. OAuth client is cluster-specific with dynamic URLs
# 2. Client secret is generated at runtime
# 3. No need to push cluster-specific configs to Git
# 4. Simpler and cleaner for multi-cluster deployments

resource "null_resource" "create_keycloak_oauth_client" {
  count = var.deploy_keycloak && var.deploy_developerhub ? 1 : 0

  depends_on = [
    null_resource.process_gitops_templates,
    null_resource.create_keycloak_application
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
      KEYCLOAK_READY=false
      KEYCLOAK_URL=""
      while [ $ELAPSED -lt $MAX_WAIT ]; do
        if oc --kubeconfig=$KUBECONFIG get route keycloak -n rhbk >/dev/null 2>&1; then
          KEYCLOAK_URL=$(oc --kubeconfig=$KUBECONFIG get route keycloak -n rhbk -o jsonpath='{.spec.host}')
          # Check if Keycloak is responding (check master realm first)
          if curl -k -s "https://$KEYCLOAK_URL/realms/master" 2>/dev/null | grep -q "master"; then
            echo "   Keycloak is ready at: https://$KEYCLOAK_URL"
            KEYCLOAK_READY=true
            break
          fi
        fi
        echo "   Waiting... ($ELAPSED/$MAX_WAIT seconds)"
        sleep 10
        ELAPSED=$((ELAPSED + 10))
      done
      
      if [ "$KEYCLOAK_READY" != "true" ]; then
        echo "ERROR: Keycloak did not become ready within $MAX_WAIT seconds"
        exit 1
      fi
      
      # Additional wait to ensure Keycloak is fully initialized
      echo "   Waiting additional 10 seconds for Keycloak to fully initialize..."
      sleep 10
      
      # Get cluster domain
      CLUSTER_DOMAIN="${data.external.cluster_domain[0].result.domain}"
      OIDC_CLIENT_SECRET="${random_password.oidc_client_secret[0].result}"
      
      echo ""
      echo "3. Getting Keycloak admin credentials..."
      KEYCLOAK_URL=$(oc --kubeconfig=$KUBECONFIG get route keycloak -n rhbk -o jsonpath='{.spec.host}')
      
      # Try to get admin password from secret (try multiple possible secret names)
      ADMIN_PASS=""
      SECRET_NAMES="sample-kc-initial-admin keycloak-initial-admin initial-admin"
      for SECRET_NAME in $SECRET_NAMES; do
        if oc --kubeconfig=$KUBECONFIG get secret "$SECRET_NAME" -n rhbk >/dev/null 2>&1; then
          ADMIN_PASS=$(oc --kubeconfig=$KUBECONFIG get secret "$SECRET_NAME" -n rhbk -o jsonpath='{.data.password}' 2>/dev/null | base64 -d)
          if [ -n "$ADMIN_PASS" ]; then
            echo "   Found admin password in secret: $SECRET_NAME"
            break
          fi
        fi
      done
      
      if [ -z "$ADMIN_PASS" ]; then
        echo "ERROR: Could not find Keycloak admin password secret"
        echo "   Tried secrets: $SECRET_NAMES"
        echo "   Available secrets in rhbk namespace:"
        oc --kubeconfig=$KUBECONFIG get secrets -n rhbk | grep -i admin || echo "   No admin secrets found"
        exit 1
      fi
      
      # Get admin token
      echo ""
      echo "4. Getting admin token..."
      TOKEN_RESPONSE=$(curl -k -s -X POST "https://$KEYCLOAK_URL/realms/master/protocol/openid-connect/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "username=admin" \
        -d "password=$ADMIN_PASS" \
        -d "grant_type=password" \
        -d "client_id=admin-cli")
      
      # Check if response is valid JSON and contains access_token
      if ! echo "$TOKEN_RESPONSE" | jq -e '.access_token' >/dev/null 2>&1; then
        echo "ERROR: Failed to get admin token from Keycloak"
        echo "Response from Keycloak:"
        echo "$TOKEN_RESPONSE" | head -20
        echo ""
        echo "Possible issues:"
        echo "  - Admin password is incorrect"
        echo "  - Keycloak is not fully initialized"
        echo "  - Network connectivity issues"
        exit 1
      fi
      
      TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')
      
      if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
        echo "ERROR: Access token is null or empty"
        echo "Response: $TOKEN_RESPONSE"
        exit 1
      fi
      
      echo "   ✓ Admin token obtained successfully"
      
      # Wait for 'myrealm' to be created by GitOps
      echo ""
      echo "5. Waiting for 'myrealm' to be created by GitOps..."
      MAX_REALM_WAIT=600
      REALM_ELAPSED=0
      REALM_READY=false
      while [ $REALM_ELAPSED -lt $MAX_REALM_WAIT ]; do
        REALM_HTTP_CODE=$(curl -k -s -X GET "https://$KEYCLOAK_URL/admin/realms/myrealm" \
          -H "Authorization: Bearer $TOKEN" -w "%%{http_code}" -o /dev/null)
        
        if [ "$REALM_HTTP_CODE" = "200" ]; then
          echo "   ✓ Realm 'myrealm' is available (created by GitOps)"
          REALM_READY=true
          break
        fi
        
        echo "   Waiting for realm 'myrealm' to be created by GitOps... ($REALM_ELAPSED/$MAX_REALM_WAIT seconds)"
        sleep 15
        REALM_ELAPSED=$((REALM_ELAPSED + 15))
        
        # Refresh token if it's been a while (tokens expire after 60 seconds by default)
        # Refresh every 45 seconds to stay ahead of expiration
        if [ $REALM_ELAPSED -ge 45 ] && [ $((REALM_ELAPSED % 45)) -eq 0 ]; then
          echo "   Refreshing admin token..."
          TOKEN_RESPONSE=$(curl -k -s -X POST "https://$KEYCLOAK_URL/realms/master/protocol/openid-connect/token" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -d "username=admin" \
            -d "password=$ADMIN_PASS" \
            -d "grant_type=password" \
            -d "client_id=admin-cli")
          NEW_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token' 2>/dev/null)
          if [ -n "$NEW_TOKEN" ] && [ "$NEW_TOKEN" != "null" ]; then
            TOKEN="$NEW_TOKEN"
            echo "   ✓ Token refreshed successfully"
          else
            echo "   WARNING: Failed to refresh token, will retry on next iteration"
            echo "   Response: $(echo "$TOKEN_RESPONSE" | head -3)"
          fi
        fi
      done
      
      if [ "$REALM_READY" != "true" ]; then
        echo "ERROR: Realm 'myrealm' was not created by GitOps within $MAX_REALM_WAIT seconds"
        echo "   Please check:"
        echo "   1. Keycloak GitOps application is synced successfully"
        echo "   2. Keycloak instance is running and healthy"
        echo "   3. Realm configuration exists in GitOps repository"
        echo "   4. ArgoCD has successfully applied the realm configuration"
        exit 1
      fi
      
      # Check if client already exists
      echo ""
      echo "6. Checking if OAuth client exists..."
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
          echo "   Response body:"
          curl -k -s -X POST "https://$KEYCLOAK_URL/admin/realms/myrealm/clients" \
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
            }" || true
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
        
        if [ "$HTTP_CODE" = "204" ] || [ "$HTTP_CODE" = "200" ]; then
          echo "   ✓ OAuth client updated successfully"
        else
          echo "   ERROR: Failed to update client (HTTP $HTTP_CODE)"
          echo "   Response body:"
          curl -k -s -X PUT "https://$KEYCLOAK_URL/admin/realms/myrealm/clients/$EXISTING_CLIENT" \
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
            }" || true
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

