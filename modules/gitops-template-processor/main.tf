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

      # Process Developer Hub templates if enabled
      if [ "${var.process_developerhub_templates}" = "true" ]; then
        echo ""
        echo "3. Processing Developer Hub configuration..."
        DEVHUB_NS="${var.devhub_namespace}"

        # Ensure namespace exists
        oc --kubeconfig=$KUBECONFIG get namespace "$DEVHUB_NS" >/dev/null 2>&1 || \
          oc --kubeconfig=$KUBECONFIG create namespace "$DEVHUB_NS"

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
    cluster_id      = var.cluster_id
    cluster_api_url = var.cluster_api_url
    timestamp       = var.force_update ? timestamp() : "static"
  }
}
