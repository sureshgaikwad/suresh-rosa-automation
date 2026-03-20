################################################################################
# Keycloak OAuth Module
#
# Creates and configures Keycloak OAuth client for applications like Developer Hub.
# This module handles:
# - Waiting for Keycloak to be ready
# - Creating OAuth client in the specified realm
# - Configuring redirect URIs and client scopes
################################################################################

resource "null_resource" "create_keycloak_oauth_client" {
  count = var.enabled ? 1 : 0

  triggers = {
    cluster_id                   = var.cluster_id
    oidc_client_secret           = var.oidc_client_secret
    cluster_domain               = var.cluster_domain
    create_bootstrap_user        = tostring(var.create_bootstrap_user)
    bootstrap_username           = var.bootstrap_username
    bootstrap_email              = var.bootstrap_email
    bootstrap_password           = var.bootstrap_password
    bootstrap_password_temporary = tostring(var.bootstrap_password_temporary)
  }

  provisioner "local-exec" {
    command = <<-EOT
      #!/bin/bash
      set -e
      
      echo "============================================================"
      echo "Creating Keycloak OAuth Client"
      echo "============================================================"
      echo ""

      # Login to cluster
      echo "1. Logging into cluster..."
      export OC_USERNAME="${var.cluster_admin_username}"
      export OC_PASSWORD="${var.cluster_admin_password}"
      export OC_API_URL="${var.cluster_api_url}"
      source ${path.root}/scripts/oc-login.sh
      
      # Wait for Keycloak to be ready
      echo ""
      echo "2. Waiting for Keycloak to be ready (namespace=${var.keycloak_namespace}, route=${var.keycloak_route_name}, max_wait=${var.keycloak_wait_timeout}s)..."
      MAX_WAIT=${var.keycloak_wait_timeout}
      ELAPSED=0
      KEYCLOAK_READY=false
      KEYCLOAK_URL=""
      ROUTE_EXISTS=""
      CURL_OK=""
      while [ $ELAPSED -lt $MAX_WAIT ]; do
        ROUTE_EXISTS=""
        CURL_OK=""
        if oc --kubeconfig=$KUBECONFIG get route ${var.keycloak_route_name} -n ${var.keycloak_namespace} >/dev/null 2>&1; then
          ROUTE_EXISTS="yes"
          KEYCLOAK_URL=$(oc --kubeconfig=$KUBECONFIG get route ${var.keycloak_route_name} -n ${var.keycloak_namespace} -o jsonpath='{.spec.host}')
          if [ -n "$KEYCLOAK_URL" ]; then
            if curl -k -s --connect-timeout 10 --max-time 15 "https://$KEYCLOAK_URL/realms/master" 2>/dev/null | grep -q "master"; then
              CURL_OK="yes"
              echo "   Keycloak is ready at: https://$KEYCLOAK_URL"
              KEYCLOAK_READY=true
              break
            fi
          fi
        fi
        if [ $((ELAPSED % 30)) -eq 0 ] && [ $ELAPSED -gt 0 ]; then
          echo "   Diagnostic: route_exists=$ROUTE_EXISTS curl_ok=$CURL_OK (check: oc get pods -n ${var.keycloak_namespace}; oc get route -n ${var.keycloak_namespace})"
        fi
        echo "   Waiting... ($ELAPSED/$MAX_WAIT seconds)"
        sleep 10
        ELAPSED=$((ELAPSED + 10))
      done
      
      if [ "$KEYCLOAK_READY" != "true" ]; then
        echo "ERROR: Keycloak did not become ready within $MAX_WAIT seconds"
        echo "Diagnostics:"
        echo "  Route '${var.keycloak_route_name}' in namespace '${var.keycloak_namespace}':"
        oc --kubeconfig=$KUBECONFIG get route ${var.keycloak_route_name} -n ${var.keycloak_namespace} 2>&1 || true
        echo "  Pods in namespace '${var.keycloak_namespace}':"
        oc --kubeconfig=$KUBECONFIG get pods -n ${var.keycloak_namespace} 2>&1 || true
        echo "  If Keycloak pod is still starting or in CrashLoopBackOff, increase keycloak_wait_timeout (e.g. 600) and re-apply."
        exit 1
      fi
      
      sleep 10
      
      CLUSTER_DOMAIN="${var.cluster_domain}"
      OIDC_CLIENT_SECRET="${var.oidc_client_secret}"
      
      echo ""
      echo "3. Getting Keycloak admin credentials..."
      
      ADMIN_PASS=""
      SECRET_NAMES="${var.keycloak_admin_secret_names}"
      for SECRET_NAME in $SECRET_NAMES; do
        if oc --kubeconfig=$KUBECONFIG get secret "$SECRET_NAME" -n ${var.keycloak_namespace} >/dev/null 2>&1; then
          ADMIN_PASS=$(oc --kubeconfig=$KUBECONFIG get secret "$SECRET_NAME" -n ${var.keycloak_namespace} -o jsonpath='{.data.password}' 2>/dev/null | base64 -d)
          if [ -n "$ADMIN_PASS" ]; then
            echo "   Found admin password in secret: $SECRET_NAME"
            break
          fi
        fi
      done
      
      if [ -z "$ADMIN_PASS" ]; then
        echo "ERROR: Could not find Keycloak admin password secret"
        exit 1
      fi
      
      echo ""
      echo "4. Getting admin token..."
      TOKEN_RESPONSE=$(curl -k -s -X POST "https://$KEYCLOAK_URL/realms/master/protocol/openid-connect/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "username=admin" \
        -d "password=$ADMIN_PASS" \
        -d "grant_type=password" \
        -d "client_id=admin-cli")
      
      if ! echo "$TOKEN_RESPONSE" | jq -e '.access_token' >/dev/null 2>&1; then
        echo "ERROR: Failed to get admin token from Keycloak"
        exit 1
      fi
      
      TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')
      echo "   ✓ Admin token obtained successfully"
      
      # Wait for realm to be created by GitOps
      echo ""
      echo "5. Waiting for '${var.keycloak_realm}' to be created by GitOps..."
      MAX_REALM_WAIT=${var.realm_wait_timeout}
      REALM_ELAPSED=0
      REALM_READY=false
      while [ $REALM_ELAPSED -lt $MAX_REALM_WAIT ]; do
        REALM_HTTP_CODE=$(curl -k -s -X GET "https://$KEYCLOAK_URL/admin/realms/${var.keycloak_realm}" \
          -H "Authorization: Bearer $TOKEN" -w "%%{http_code}" -o /dev/null)
        
        if [ "$REALM_HTTP_CODE" = "200" ]; then
          echo "   ✓ Realm '${var.keycloak_realm}' is available"
          REALM_READY=true
          break
        fi
        
        echo "   Waiting for realm... ($REALM_ELAPSED/$MAX_REALM_WAIT seconds)"
        sleep 15
        REALM_ELAPSED=$((REALM_ELAPSED + 15))
        
        # Refresh token periodically
        if [ $((REALM_ELAPSED % 45)) -eq 0 ]; then
          TOKEN_RESPONSE=$(curl -k -s -X POST "https://$KEYCLOAK_URL/realms/master/protocol/openid-connect/token" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -d "username=admin" \
            -d "password=$ADMIN_PASS" \
            -d "grant_type=password" \
            -d "client_id=admin-cli")
          NEW_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token' 2>/dev/null)
          if [ -n "$NEW_TOKEN" ] && [ "$NEW_TOKEN" != "null" ]; then
            TOKEN="$NEW_TOKEN"
          fi
        fi
      done
      
      if [ "$REALM_READY" != "true" ]; then
        echo "ERROR: Realm '${var.keycloak_realm}' was not created within $MAX_REALM_WAIT seconds"
        exit 1
      fi
      
      # Create or update OAuth client
      echo ""
      echo "6. Creating/updating OAuth client '${var.client_id}'..."
      EXISTING_CLIENT=$(curl -k -s -X GET "https://$KEYCLOAK_URL/admin/realms/${var.keycloak_realm}/clients" \
        -H "Authorization: Bearer $TOKEN" | jq -r '.[] | select(.clientId=="${var.client_id}") | .id')
      
      REDIRECT_URIS='${jsonencode(var.redirect_uris)}'
      WEB_ORIGINS='${jsonencode(var.web_origins)}'
      
      if [ -z "$EXISTING_CLIENT" ]; then
        HTTP_CODE=$(curl -k -s -w "%%{http_code}" -o /dev/null -X POST "https://$KEYCLOAK_URL/admin/realms/${var.keycloak_realm}/clients" \
          -H "Authorization: Bearer $TOKEN" \
          -H "Content-Type: application/json" \
          -d "{
            \"clientId\": \"${var.client_id}\",
            \"name\": \"${var.client_name}\",
            \"description\": \"${var.client_description}\",
            \"enabled\": true,
            \"protocol\": \"openid-connect\",
            \"publicClient\": false,
            \"standardFlowEnabled\": true,
            \"implicitFlowEnabled\": false,
            \"directAccessGrantsEnabled\": false,
            \"secret\": \"$OIDC_CLIENT_SECRET\",
            \"redirectUris\": $REDIRECT_URIS,
            \"webOrigins\": $WEB_ORIGINS,
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
        HTTP_CODE=$(curl -k -s -w "%%{http_code}" -o /dev/null -X PUT "https://$KEYCLOAK_URL/admin/realms/${var.keycloak_realm}/clients/$EXISTING_CLIENT" \
          -H "Authorization: Bearer $TOKEN" \
          -H "Content-Type: application/json" \
          -d "{
            \"clientId\": \"${var.client_id}\",
            \"name\": \"${var.client_name}\",
            \"description\": \"${var.client_description}\",
            \"enabled\": true,
            \"protocol\": \"openid-connect\",
            \"publicClient\": false,
            \"standardFlowEnabled\": true,
            \"implicitFlowEnabled\": false,
            \"directAccessGrantsEnabled\": false,
            \"secret\": \"$OIDC_CLIENT_SECRET\",
            \"redirectUris\": $REDIRECT_URIS,
            \"webOrigins\": $WEB_ORIGINS,
            \"defaultClientScopes\": [\"openid\", \"email\", \"profile\", \"roles\", \"web-origins\"],
            \"optionalClientScopes\": [\"address\", \"phone\", \"offline_access\"]
          }")
        
        if [ "$HTTP_CODE" = "204" ] || [ "$HTTP_CODE" = "200" ]; then
          echo "   ✓ OAuth client updated successfully"
        else
          echo "   ERROR: Failed to update client (HTTP $HTTP_CODE)"
          exit 1
        fi
      fi
      
      if [ "${var.create_bootstrap_user}" = "true" ]; then
        echo ""
        echo "7. Creating/updating bootstrap user '${var.bootstrap_username}' in realm '${var.keycloak_realm}'..."
        BOOTSTRAP_USERNAME="${var.bootstrap_username}"
        BOOTSTRAP_EMAIL="${var.bootstrap_email}"
        BOOTSTRAP_FIRST_NAME="${var.bootstrap_first_name}"
        BOOTSTRAP_LAST_NAME="${var.bootstrap_last_name}"
        BOOTSTRAP_PASSWORD="${var.bootstrap_password}"
        BOOTSTRAP_PASSWORD_TEMPORARY="${var.bootstrap_password_temporary}"

        if [ -z "$BOOTSTRAP_PASSWORD" ]; then
          echo "ERROR: bootstrap_password is empty while create_bootstrap_user=true"
          exit 1
        fi

        # Prefer username match, then fall back to email match to handle
        # realms that enforce unique emails and already have a user record.
        EXISTING_USER_ID=$(curl -k -s -X GET "https://$KEYCLOAK_URL/admin/realms/${var.keycloak_realm}/users?username=$BOOTSTRAP_USERNAME" \
          -H "Authorization: Bearer $TOKEN" | jq -r '.[] | select(.username=="'"$BOOTSTRAP_USERNAME"'") | .id' | head -n1)
        if [ -z "$EXISTING_USER_ID" ] && [ -n "$BOOTSTRAP_EMAIL" ]; then
          EXISTING_USER_ID=$(curl -k -s -X GET "https://$KEYCLOAK_URL/admin/realms/${var.keycloak_realm}/users?email=$BOOTSTRAP_EMAIL" \
            -H "Authorization: Bearer $TOKEN" | jq -r '.[] | select(.email=="'"$BOOTSTRAP_EMAIL"'") | .id' | head -n1)
        fi

        USER_PAYLOAD=$(jq -n \
          --arg username "$BOOTSTRAP_USERNAME" \
          --arg email "$BOOTSTRAP_EMAIL" \
          --arg firstName "$BOOTSTRAP_FIRST_NAME" \
          --arg lastName "$BOOTSTRAP_LAST_NAME" \
          '{
            username: $username,
            email: $email,
            firstName: $firstName,
            lastName: $lastName,
            enabled: true,
            emailVerified: true
          }')

        if [ -z "$EXISTING_USER_ID" ]; then
          HTTP_CODE=$(curl -k -s -w "%%{http_code}" -o /dev/null -X POST "https://$KEYCLOAK_URL/admin/realms/${var.keycloak_realm}/users" \
            -H "Authorization: Bearer $TOKEN" \
            -H "Content-Type: application/json" \
            -d "$USER_PAYLOAD")
          if [ "$HTTP_CODE" = "409" ]; then
            # Conflict usually means username or email already exists. Resolve by
            # looking up existing user and updating it idempotently.
            if [ -n "$BOOTSTRAP_EMAIL" ]; then
              EXISTING_USER_ID=$(curl -k -s -X GET "https://$KEYCLOAK_URL/admin/realms/${var.keycloak_realm}/users?email=$BOOTSTRAP_EMAIL" \
                -H "Authorization: Bearer $TOKEN" | jq -r '.[] | select(.email=="'"$BOOTSTRAP_EMAIL"'") | .id' | head -n1)
            fi
            if [ -z "$EXISTING_USER_ID" ]; then
              EXISTING_USER_ID=$(curl -k -s -X GET "https://$KEYCLOAK_URL/admin/realms/${var.keycloak_realm}/users?username=$BOOTSTRAP_USERNAME" \
                -H "Authorization: Bearer $TOKEN" | jq -r '.[] | select(.username=="'"$BOOTSTRAP_USERNAME"'") | .id' | head -n1)
            fi
            if [ -z "$EXISTING_USER_ID" ]; then
              echo "ERROR: Bootstrap user conflict detected (HTTP 409), but existing user could not be resolved"
              exit 1
            fi
            HTTP_CODE=$(curl -k -s -w "%%{http_code}" -o /dev/null -X PUT "https://$KEYCLOAK_URL/admin/realms/${var.keycloak_realm}/users/$EXISTING_USER_ID" \
              -H "Authorization: Bearer $TOKEN" \
              -H "Content-Type: application/json" \
              -d "$USER_PAYLOAD")
            if [ "$HTTP_CODE" != "204" ] && [ "$HTTP_CODE" != "200" ]; then
              echo "ERROR: Failed to update existing bootstrap user after conflict (HTTP $HTTP_CODE)"
              exit 1
            fi
            echo "   ✓ Bootstrap user conflict resolved by updating existing user"
          elif [ "$HTTP_CODE" != "201" ]; then
            echo "ERROR: Failed to create bootstrap user (HTTP $HTTP_CODE)"
            exit 1
          else
            EXISTING_USER_ID=$(curl -k -s -X GET "https://$KEYCLOAK_URL/admin/realms/${var.keycloak_realm}/users?username=$BOOTSTRAP_USERNAME" \
              -H "Authorization: Bearer $TOKEN" | jq -r '.[] | select(.username=="'"$BOOTSTRAP_USERNAME"'") | .id' | head -n1)
            echo "   ✓ Bootstrap user created"
          fi
        else
          HTTP_CODE=$(curl -k -s -w "%%{http_code}" -o /dev/null -X PUT "https://$KEYCLOAK_URL/admin/realms/${var.keycloak_realm}/users/$EXISTING_USER_ID" \
            -H "Authorization: Bearer $TOKEN" \
            -H "Content-Type: application/json" \
            -d "$USER_PAYLOAD")
          if [ "$HTTP_CODE" != "204" ] && [ "$HTTP_CODE" != "200" ]; then
            echo "ERROR: Failed to update bootstrap user (HTTP $HTTP_CODE)"
            exit 1
          fi
          echo "   ✓ Bootstrap user updated"
        fi

        PASSWORD_PAYLOAD=$(jq -n \
          --arg value "$BOOTSTRAP_PASSWORD" \
          --argjson temporary "$BOOTSTRAP_PASSWORD_TEMPORARY" \
          '{
            type: "password",
            value: $value,
            temporary: $temporary
          }')
        HTTP_CODE=$(curl -k -s -w "%%{http_code}" -o /dev/null -X PUT "https://$KEYCLOAK_URL/admin/realms/${var.keycloak_realm}/users/$EXISTING_USER_ID/reset-password" \
          -H "Authorization: Bearer $TOKEN" \
          -H "Content-Type: application/json" \
          -d "$PASSWORD_PAYLOAD")
        if [ "$HTTP_CODE" != "204" ] && [ "$HTTP_CODE" != "200" ]; then
          echo "ERROR: Failed to set bootstrap user password (HTTP $HTTP_CODE)"
          exit 1
        fi
        echo "   ✓ Bootstrap user password configured"
      fi

      rm -f $KUBECONFIG
      
      echo ""
      echo "============================================================"
      echo "✓ OAuth Client Configuration Complete"
      echo "============================================================"
    EOT
  }
}
