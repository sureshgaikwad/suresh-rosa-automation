################################################################################
# GitOps Template Processor Module
#
# Processes cluster-specific configurations and applies them directly to the
# cluster via 'oc apply'. No git push required -- the processed config is
# stored as a ConfigMap on the cluster so that Developer Hub (and other
# components) can consume it.
################################################################################

resource "null_resource" "process_gitops_templates" {
  count = var.enabled ? 1 : 0

  provisioner "local-exec" {
    command = <<-EOT
      #!/bin/bash
      set -e

      echo "============================================================"
      echo "Processing GitOps Templates"
      echo "============================================================"
      echo ""

      # Login to cluster
      echo "1. Logging into cluster..."
      export OC_USERNAME="${var.cluster_admin_username}"
      export OC_PASSWORD="${var.cluster_admin_password}"
      export OC_API_URL="${var.cluster_api_url}"
      source ${path.root}/scripts/oc-login.sh

      # Get cluster domain dynamically
      echo ""
      echo "2. Detecting cluster domain..."
      CLUSTER_DOMAIN=$(oc --kubeconfig=$KUBECONFIG get ingress.config.openshift.io/cluster -o jsonpath='{.spec.domain}')
      echo "   Domain: $CLUSTER_DOMAIN"
      CLUSTER_BASE_DOMAIN=$(echo "$CLUSTER_DOMAIN" | sed 's/^apps\.//')

      DEVSPACES_ROUTE_HOST=$(oc --kubeconfig=$KUBECONFIG get route devspaces -n openshift-devspaces -o jsonpath='{.spec.host}' 2>/dev/null || true)
      if [ -n "$DEVSPACES_ROUTE_HOST" ]; then
        DEVSPACES_BASE_URL="https://$DEVSPACES_ROUTE_HOST"
      else
        DEVSPACES_BASE_URL="https://devspaces.$CLUSTER_DOMAIN"
      fi

      ARGOCD_ROUTE_HOST=$(oc --kubeconfig=$KUBECONFIG get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}' 2>/dev/null || true)
      if [ -n "$ARGOCD_ROUTE_HOST" ]; then
        ARGOCD_APPLICATIONS_URL="https://$ARGOCD_ROUTE_HOST/applications"
      else
        ARGOCD_APPLICATIONS_URL="https://openshift-gitops-server-openshift-gitops.$CLUSTER_DOMAIN/applications"
      fi

      OPENAI_API_BASE='${var.model_api_base}'
      OPENAI_MODEL_ID='${var.model_id}'
      OPENAI_API_TARGET="$${OPENAI_API_BASE%/v1}"

      # Process Developer Hub templates if enabled
      if [ "${var.process_developerhub_templates}" = "true" ]; then
        echo ""
        echo "3. Processing Developer Hub configuration..."
        DEVHUB_NS="${var.devhub_namespace}"

        # Ensure namespace exists
        oc --kubeconfig=$KUBECONFIG get namespace "$DEVHUB_NS" >/dev/null 2>&1 || \
          oc --kubeconfig=$KUBECONFIG create namespace "$DEVHUB_NS"

        # Mitigate ArgoCD deadlock with WaitForFirstConsumer PVC:
        # the app can wait on PVC health before Backstage pod exists.
        # If/when the PVC appears, mark it SkipWait so sync can progress.
        MAX_PVC_WAIT=600
        PVC_WAIT_ELAPSED=0
        while [ $PVC_WAIT_ELAPSED -lt $MAX_PVC_WAIT ]; do
          if oc --kubeconfig=$KUBECONFIG -n "$DEVHUB_NS" get pvc dynamic-plugins-root >/dev/null 2>&1; then
            oc --kubeconfig=$KUBECONFIG -n "$DEVHUB_NS" annotate pvc dynamic-plugins-root \
              argocd.argoproj.io/sync-options=SkipWait=true --overwrite >/dev/null 2>&1 || true
            echo "   + Annotated pvc/dynamic-plugins-root with ArgoCD SkipWait=true"
            break
          fi
          sleep 10
          PVC_WAIT_ELAPSED=$((PVC_WAIT_ELAPSED + 10))
        done

        # Create/update a ConfigMap with the cluster domain so Developer Hub
        # can reference it without needing pre-processed templates in git.
        oc --kubeconfig=$KUBECONFIG apply -f - <<YAML
apiVersion: v1
kind: ConfigMap
metadata:
  name: developer-hub-cluster-config
  namespace: $DEVHUB_NS
  labels:
    app.kubernetes.io/managed-by: terraform
data:
  CLUSTER_DOMAIN: "$CLUSTER_DOMAIN"
  CLUSTER_ID: "${var.cluster_id}"
  BACKSTAGE_BASE_URL: "https://backstage-developer-hub-$DEVHUB_NS.$CLUSTER_DOMAIN"
YAML
        echo "   + ConfigMap developer-hub-cluster-config applied in $DEVHUB_NS"

        # Render and apply developer-hub-app-config from template
        APP_CONFIG_TEMPLATE="${var.app_config_template_path}"
        if [ -n "$APP_CONFIG_TEMPLATE" ] && [ -f "$APP_CONFIG_TEMPLATE" ]; then
          echo "   + Processing app-config template..."
          export APP_CONFIG_TEMPLATE
          export CLUSTER_BASE_DOMAIN
          python3 - <<'PY' | oc --kubeconfig=$KUBECONFIG apply -f -
import os
template = os.environ["APP_CONFIG_TEMPLATE"]
domain = os.environ["CLUSTER_BASE_DOMAIN"]
with open(template, "r", encoding="utf-8") as f:
    content = f.read()
content = content.replace("{{CLUSTER_DOMAIN}}", domain)
content = content.replace("{{cluster_domain}}", domain)
if "{{CLUSTER_DOMAIN}}" in content or "{{cluster_domain}}" in content:
    raise SystemExit("Unresolved cluster domain placeholder found in app-config template")
print(content, end="")
PY
          echo "   + ConfigMap developer-hub-app-config applied in $DEVHUB_NS"
        else
          echo "   ! app-config template not found, skipping: $APP_CONFIG_TEMPLATE"
        fi

        # Render and apply developer-hub-auth-secrets from template
        AUTH_SECRET_TEMPLATE="${var.auth_secret_template_path}"
        if [ -n "$AUTH_SECRET_TEMPLATE" ] && [ -f "$AUTH_SECRET_TEMPLATE" ]; then
          echo "   + Processing auth-secret template..."
          if [ -n "$ARGOCD_ROUTE_HOST" ]; then
            ARGOCD_URL="https://$ARGOCD_ROUTE_HOST"
          else
            ARGOCD_URL="https://openshift-gitops-server-openshift-gitops.$CLUSTER_DOMAIN"
          fi
          ARGOCD_TOKEN=$(oc --kubeconfig=$KUBECONFIG create token openshift-gitops-argocd-server -n openshift-gitops --duration=87600h 2>/dev/null || true)

          OIDC_CLIENT_SECRET=$(printf '%s' '${base64encode(var.oidc_client_secret)}' | base64 --decode)
          SESSION_SECRET=$(printf '%s' '${base64encode(var.session_secret)}' | base64 --decode)

          export AUTH_SECRET_TEMPLATE
          export CLUSTER_DOMAIN
          export ARGOCD_URL
          export ARGOCD_TOKEN
          export OIDC_CLIENT_SECRET
          export SESSION_SECRET
          python3 - <<'PY' | oc --kubeconfig=$KUBECONFIG apply -f -
import os
template = os.environ["AUTH_SECRET_TEMPLATE"]
replacements = {
    "{{OIDC_CLIENT_SECRET}}": os.environ.get("OIDC_CLIENT_SECRET", ""),
    "{{SESSION_SECRET}}": os.environ.get("SESSION_SECRET", ""),
    "{{CLUSTER_DOMAIN}}": os.environ.get("CLUSTER_DOMAIN", ""),
    "{{cluster_domain}}": os.environ.get("CLUSTER_DOMAIN", ""),
    "{{ARGOCD_URL}}": os.environ.get("ARGOCD_URL", ""),
    "{{ARGOCD_TOKEN}}": os.environ.get("ARGOCD_TOKEN", ""),
}
with open(template, "r", encoding="utf-8") as f:
    content = f.read()
for src, dst in replacements.items():
    content = content.replace(src, dst)
for placeholder in ("{{OIDC_CLIENT_SECRET}}", "{{SESSION_SECRET}}", "{{CLUSTER_DOMAIN}}", "{{cluster_domain}}", "{{ARGOCD_URL}}", "{{ARGOCD_TOKEN}}"):
    if placeholder in content:
        raise SystemExit(f"Unresolved placeholder found in auth-secret template: {placeholder}")
print(content, end="")
PY
          echo "   + Secret developer-hub-auth-secrets applied in $DEVHUB_NS"
        else
          echo "   ! auth-secret template not found, skipping: $AUTH_SECRET_TEMPLATE"
        fi

        if [ "${var.process_agentic_templates}" = "true" ]; then
          echo "   + Processing agentic templates..."
          AGENTIC_TEMPLATE_PATH="${var.agentic_template_path}"
          AGENTIC_DEVFILE_PATH="${var.agentic_devfile_path}"
          AGENTIC_SNIPPET_PATH="${var.agentic_app_config_snippet_path}"

          render_template() {
            local src="$1"
            local out="$2"
            python3 - <<'PY'
import os
src = os.environ["RENDER_SRC"]
dst = os.environ["RENDER_DST"]
replacements = {
    "{{CLUSTER_DOMAIN}}": os.environ.get("CLUSTER_DOMAIN", ""),
    "{{cluster_domain}}": os.environ.get("CLUSTER_DOMAIN", ""),
    "{{DEVSPACES_BASE_URL}}": os.environ.get("DEVSPACES_BASE_URL", ""),
    "{{ARGOCD_APPLICATIONS_URL}}": os.environ.get("ARGOCD_APPLICATIONS_URL", ""),
    "{{OPENAI_API_BASE}}": os.environ.get("OPENAI_API_BASE", ""),
    "{{OPENAI_API_TARGET}}": os.environ.get("OPENAI_API_TARGET", ""),
    "{{OPENAI_MODEL_ID}}": os.environ.get("OPENAI_MODEL_ID", ""),
}
with open(src, "r", encoding="utf-8") as f:
    content = f.read()
for key, val in replacements.items():
    content = content.replace(key, val)
# Only fail for placeholders this renderer is responsible for.
# Backstage scaffolder expressions are valid and must remain intact.
for placeholder in replacements.keys():
    if placeholder in content:
        raise SystemExit(f"Unresolved placeholder found after rendering: {src} ({placeholder})")
with open(dst, "w", encoding="utf-8") as f:
    f.write(content)
PY
          }

          if [ -f "$AGENTIC_TEMPLATE_PATH" ]; then
            export RENDER_SRC="$AGENTIC_TEMPLATE_PATH"
            export RENDER_DST="/tmp/template-ostoy-ai-starter.rendered.yaml"
            export CLUSTER_DOMAIN DEVSPACES_BASE_URL ARGOCD_APPLICATIONS_URL OPENAI_API_BASE OPENAI_API_TARGET OPENAI_MODEL_ID
            render_template "$RENDER_SRC" "$RENDER_DST"
            oc --kubeconfig=$KUBECONFIG create configmap developer-hub-agentic-template \
              -n "$DEVHUB_NS" \
              --from-file=template-ostoy-ai-starter.yaml="$RENDER_DST" \
              --dry-run=client -o yaml | oc --kubeconfig=$KUBECONFIG apply -f -
          fi

          if [ -f "$AGENTIC_DEVFILE_PATH" ]; then
            export RENDER_SRC="$AGENTIC_DEVFILE_PATH"
            export RENDER_DST="/tmp/devfile-factory-continue.rendered.yaml"
            export CLUSTER_DOMAIN DEVSPACES_BASE_URL ARGOCD_APPLICATIONS_URL OPENAI_API_BASE OPENAI_API_TARGET OPENAI_MODEL_ID
            render_template "$RENDER_SRC" "$RENDER_DST"
            oc --kubeconfig=$KUBECONFIG create configmap developer-hub-agentic-devfile \
              -n "$DEVHUB_NS" \
              --from-file=devfile-factory-continue.yaml="$RENDER_DST" \
              --dry-run=client -o yaml | oc --kubeconfig=$KUBECONFIG apply -f -
          fi

          if [ -f "$AGENTIC_SNIPPET_PATH" ]; then
            export RENDER_SRC="$AGENTIC_SNIPPET_PATH"
            export RENDER_DST="/tmp/app-config-agentic-snippet.rendered.yaml"
            export CLUSTER_DOMAIN DEVSPACES_BASE_URL ARGOCD_APPLICATIONS_URL OPENAI_API_BASE OPENAI_API_TARGET OPENAI_MODEL_ID
            render_template "$RENDER_SRC" "$RENDER_DST"
            oc --kubeconfig=$KUBECONFIG create configmap developer-hub-agentic-config-snippet \
              -n "$DEVHUB_NS" \
              --from-file=app-config-agentic-snippet.yaml="$RENDER_DST" \
              --dry-run=client -o yaml | oc --kubeconfig=$KUBECONFIG apply -f -
          fi

          # Ensure Backstage CR consumes the rendered ConfigMaps.
          # On fresh clusters, the CR may not exist yet while Argo CD sync is still progressing.
          MAX_BACKSTAGE_WAIT=600
          BACKSTAGE_WAIT_ELAPSED=0
          BACKSTAGE_READY=false
          while [ $BACKSTAGE_WAIT_ELAPSED -lt $MAX_BACKSTAGE_WAIT ]; do
            if oc --kubeconfig=$KUBECONFIG -n "$DEVHUB_NS" get backstage developer-hub >/dev/null 2>&1; then
              BACKSTAGE_READY=true
              break
            fi
            echo "   Waiting for Backstage CR 'developer-hub' in namespace '$DEVHUB_NS'... ($BACKSTAGE_WAIT_ELAPSED/$MAX_BACKSTAGE_WAIT seconds)"
            sleep 10
            BACKSTAGE_WAIT_ELAPSED=$((BACKSTAGE_WAIT_ELAPSED + 10))
          done

          if [ "$BACKSTAGE_READY" = "true" ]; then
            oc --kubeconfig=$KUBECONFIG -n "$DEVHUB_NS" get backstage developer-hub -o json > /tmp/backstage-agentic.json
            python3 - <<'PY'
import json
from pathlib import Path
p = Path("/tmp/backstage-agentic.json")
obj = json.loads(p.read_text())
app = obj.setdefault("spec", {}).setdefault("application", {})
app_cfg = app.setdefault("appConfig", {})
cfg_maps = app_cfg.setdefault("configMaps", [])
if not any(isinstance(x, dict) and x.get("name") == "developer-hub-agentic-config-snippet" for x in cfg_maps):
    cfg_maps.append({"name": "developer-hub-agentic-config-snippet"})
extra = app.setdefault("extraFiles", {})
extra.setdefault("mountPath", "/opt/app-root/src")
extra_maps = extra.setdefault("configMaps", [])
wanted = [
    {"name": "developer-hub-agentic-template", "key": "template-ostoy-ai-starter.yaml"},
    {"name": "developer-hub-agentic-devfile", "key": "devfile-factory-continue.yaml"},
]
for entry in wanted:
    if not any(isinstance(x, dict) and x.get("name") == entry["name"] and x.get("key") == entry["key"] for x in extra_maps):
        extra_maps.append(entry)
Path("/tmp/backstage-agentic.patched.json").write_text(json.dumps(obj))
PY
            oc --kubeconfig=$KUBECONFIG apply -f /tmp/backstage-agentic.patched.json
            echo "   + Agentic template/devfile/snippet applied and Backstage CR patched"
          else
            echo "   ! Backstage CR 'developer-hub' not available after $${MAX_BACKSTAGE_WAIT}s; skipping patch for now"
            echo "   ! Re-run terraform apply after Developer Hub sync completes to apply agentic Backstage patch"
          fi
        fi
      fi

      # Cleanup
      rm -f $KUBECONFIG

      echo ""
      echo "============================================================"
      echo "Template Processing Complete"
      echo "============================================================"
    EOT

    interpreter = ["bash", "-c"]
  }

  triggers = {
    cluster_id                  = var.cluster_id
    cluster_api_url             = var.cluster_api_url
    process_developerhub        = tostring(var.process_developerhub_templates)
    devhub_namespace            = var.devhub_namespace
    app_config_template_sha256  = var.app_config_template_path != "" && fileexists(var.app_config_template_path) ? filesha256(var.app_config_template_path) : "none"
    auth_secret_template_sha256 = var.auth_secret_template_path != "" && fileexists(var.auth_secret_template_path) ? filesha256(var.auth_secret_template_path) : "none"
    process_agentic_templates   = tostring(var.process_agentic_templates)
    agentic_template_sha256     = var.agentic_template_path != "" && fileexists(var.agentic_template_path) ? filesha256(var.agentic_template_path) : "none"
    agentic_devfile_sha256      = var.agentic_devfile_path != "" && fileexists(var.agentic_devfile_path) ? filesha256(var.agentic_devfile_path) : "none"
    agentic_snippet_sha256      = var.agentic_app_config_snippet_path != "" && fileexists(var.agentic_app_config_snippet_path) ? filesha256(var.agentic_app_config_snippet_path) : "none"
    model_api_base_sha256       = sha256(var.model_api_base)
    model_id                    = var.model_id
    oidc_client_secret_sha256   = var.oidc_client_secret != "" ? sha256(var.oidc_client_secret) : "none"
    session_secret_sha256       = var.session_secret != "" ? sha256(var.session_secret) : "none"
    timestamp                   = var.force_update ? timestamp() : "static"
  }
}
