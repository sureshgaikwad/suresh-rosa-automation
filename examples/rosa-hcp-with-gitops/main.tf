# Copyright Red Hat
# SPDX-License-Identifier: Apache-2.0

module "openshift_gitops" {
  source = "../../modules/openshift-gitops"

  enabled                = local.deploy_openshift_gitops
  cluster_id             = var.cluster_id
  cluster_api_url        = var.cluster_api_url
  cluster_admin_username = var.cluster_admin_username
  cluster_admin_password = var.cluster_admin_password
}

# Discover OpenShift apps ingress domain + default TLS secret for MaaS Gateway.
# ROSA HCP uses a cluster-id primary-cert-bundle secret (not cert-manager-ingress-cert).
data "external" "cluster_domain" {
  count = (var.deploy_keycloak || var.deploy_developerhub || local.deploy_rhoai_maas) ? 1 : 0

  depends_on = [module.openshift_gitops]

  program = ["bash", "-c", <<-EOT
    export KUBECONFIG=/tmp/rosa-kubeconfig-$$
    oc login --username="${var.cluster_admin_username}" \
             --password="${var.cluster_admin_password}" \
             "${var.cluster_api_url}" \
             --insecure-skip-tls-verify \
             --kubeconfig=$KUBECONFIG >/dev/null 2>&1
    DOMAIN=$(oc --kubeconfig=$KUBECONFIG get ingress.config.openshift.io/cluster -o jsonpath='{.spec.domain}')
    TLS=$(oc --kubeconfig=$KUBECONFIG get ingresscontroller default -n openshift-ingress-operator -o jsonpath='{.spec.defaultCertificate.name}' 2>/dev/null || true)
    if [ -z "$TLS" ] || ! oc --kubeconfig=$KUBECONFIG get secret -n openshift-ingress "$TLS" >/dev/null 2>&1; then
      TLS=$(oc --kubeconfig=$KUBECONFIG get deployment router-default -n openshift-ingress -o jsonpath='{.spec.template.spec.volumes[?(@.name=="default-certificate")].secret.secretName}' 2>/dev/null || true)
    fi
    if [ -z "$TLS" ] || ! oc --kubeconfig=$KUBECONFIG get secret -n openshift-ingress "$TLS" >/dev/null 2>&1; then
      TLS="maas-gateway-tls"
    fi
    rm -f $KUBECONFIG
    echo "{\"domain\": \"$DOMAIN\", \"tls_secret\": \"$TLS\"}"
  EOT
  ]
}

resource "random_password" "rhoai_maas_postgres" {
  count = local.deploy_rhoai_maas && var.rhoai_maas_postgres_password == "" ? 1 : 0

  length  = 24
  special = false
}

locals {
  rhoai_maas_postgres_password = var.rhoai_maas_postgres_password != "" ? var.rhoai_maas_postgres_password : try(random_password.rhoai_maas_postgres[0].result, "")
}

# MaaS DB secrets must not live in git. Create them on the cluster before Argo syncs postgres.
resource "null_resource" "rhoai_maas_postgres_secrets" {
  count = local.deploy_rhoai_maas && local.deploy_openshift_gitops ? 1 : 0

  depends_on = [module.openshift_gitops]

  provisioner "local-exec" {
    environment = {
      OC_USERNAME       = var.cluster_admin_username
      OC_PASSWORD       = var.cluster_admin_password
      OC_API_URL        = var.cluster_api_url
      POSTGRES_USER     = var.rhoai_maas_postgres_user
      POSTGRES_PASSWORD = local.rhoai_maas_postgres_password
      POSTGRES_DATABASE = var.rhoai_maas_postgres_database
    }

    command = <<-EOT
      #!/bin/bash
      set -euo pipefail

      # scripts/oc-login.sh lives at the repository root (path.root may be this example dir).
      if [ -f "${path.root}/scripts/oc-login.sh" ]; then
        source "${path.root}/scripts/oc-login.sh"
      else
        source "${path.root}/../../scripts/oc-login.sh"
      fi

      oc get ns redhat-ods-applications --kubeconfig="$KUBECONFIG" >/dev/null 2>&1 || \
        oc create ns redhat-ods-applications --kubeconfig="$KUBECONFIG"

      oc create secret generic postgres-creds \
        -n redhat-ods-applications \
        --kubeconfig="$KUBECONFIG" \
        --from-literal=POSTGRESQL_USER="$POSTGRES_USER" \
        --from-literal=POSTGRESQL_PASSWORD="$POSTGRES_PASSWORD" \
        --from-literal=POSTGRESQL_DATABASE="$POSTGRES_DATABASE" \
        --dry-run=client -o yaml | oc apply --kubeconfig="$KUBECONFIG" -f -

      oc create secret generic maas-db-config \
        -n redhat-ods-applications \
        --kubeconfig="$KUBECONFIG" \
        --from-literal=DB_CONNECTION_URL="postgresql://$${POSTGRES_USER}:$${POSTGRES_PASSWORD}@postgres:5432/$${POSTGRES_DATABASE}?sslmode=disable" \
        --dry-run=client -o yaml | oc apply --kubeconfig="$KUBECONFIG" -f -

      rm -f "$KUBECONFIG"
      echo "MaaS postgres secrets applied in redhat-ods-applications"
    EOT
  }

  triggers = {
    cluster_id = var.cluster_id
    user       = var.rhoai_maas_postgres_user
    database   = var.rhoai_maas_postgres_database
    password   = sha256(local.rhoai_maas_postgres_password)
  }
}

module "argocd_applications" {
  source   = "../../modules/argocd-application"
  for_each = local.enabled_argocd_applications

  enabled                = true
  cluster_id             = var.cluster_id
  cluster_api_url        = var.cluster_api_url
  cluster_admin_username = var.cluster_admin_username
  cluster_admin_password = var.cluster_admin_password

  application_name      = each.key
  repo_url              = each.value.repo_url
  path                  = each.value.path
  destination_namespace = each.value.namespace
  create_namespace      = lookup(each.value, "create_namespace", true)
  dependency_weight     = lookup(each.value, "dependency_weight", null)
  kustomize_components  = lookup(each.value, "kustomize_components", [])
  kustomize_patches     = lookup(each.value, "kustomize_patches", [])

  depends_on = [
    module.openshift_gitops,
    null_resource.rhoai_maas_postgres_secrets,
  ]
}

module "gitops_template_processor" {
  source = "../../modules/gitops-template-processor"

  enabled                         = (var.deploy_keycloak || var.deploy_developerhub) && local.deploy_openshift_gitops
  cluster_id                      = var.cluster_id
  cluster_api_url                 = var.cluster_api_url
  cluster_admin_username          = var.cluster_admin_username
  cluster_admin_password          = var.cluster_admin_password
  process_developerhub_templates  = var.deploy_developerhub
  app_config_template_path        = var.deploy_developerhub ? "${var.gitops_catalog_path}/operators/developer-hub/base/app-config.yaml.template" : ""
  auth_secret_template_path       = var.deploy_developerhub ? "${var.gitops_catalog_path}/operators/developer-hub/base/auth-secret.yaml.template" : ""
  process_agentic_templates       = var.deploy_developerhub
  agentic_template_path           = var.deploy_developerhub ? "${var.assets_path}/agentic-dev-platform/developer-hub/template-ostoy-ai-starter.yaml" : ""
  agentic_devfile_path            = var.deploy_developerhub ? "${var.assets_path}/agentic-dev-platform/devspaces/devfile-factory-continue.yaml" : ""
  agentic_app_config_snippet_path = var.deploy_developerhub ? "${var.assets_path}/agentic-dev-platform/developer-hub/app-config-agentic-snippet.yaml" : ""
  model_api_base                  = var.agentic_model_api_base
  model_id                        = var.agentic_model_id
  oidc_client_secret              = var.deploy_keycloak && var.deploy_developerhub ? random_password.oidc_client_secret[0].result : ""
  session_secret                  = var.deploy_developerhub ? random_password.session_secret[0].result : ""

  depends_on = [
    module.openshift_gitops,
    module.argocd_applications
  ]
}

resource "random_password" "oidc_client_secret" {
  count   = var.deploy_keycloak && var.deploy_developerhub ? 1 : 0
  length  = 32
  special = true
}

resource "random_password" "session_secret" {
  count   = var.deploy_developerhub ? 1 : 0
  length  = 32
  special = true
}

module "keycloak_oauth" {
  source = "../../modules/keycloak-oauth"

  enabled                      = var.deploy_keycloak && var.deploy_developerhub
  cluster_id                   = var.cluster_id
  cluster_api_url              = var.cluster_api_url
  cluster_admin_username       = var.cluster_admin_username
  cluster_admin_password       = var.cluster_admin_password
  cluster_domain               = local.oauth_cluster_domain
  oidc_client_secret           = var.deploy_keycloak && var.deploy_developerhub ? random_password.oidc_client_secret[0].result : ""
  redirect_uris                = local.devhub_redirect_uris
  web_origins                  = local.devhub_web_origins
  keycloak_namespace           = "rhbk"
  keycloak_route_name          = "keycloak"
  keycloak_wait_timeout        = var.keycloak_wait_timeout
  create_bootstrap_user        = var.keycloak_bootstrap_user_enabled
  bootstrap_username           = var.keycloak_bootstrap_username
  bootstrap_email              = var.keycloak_bootstrap_email
  bootstrap_first_name         = var.keycloak_bootstrap_first_name
  bootstrap_last_name          = var.keycloak_bootstrap_last_name
  bootstrap_password           = var.keycloak_bootstrap_password != "" ? var.keycloak_bootstrap_password : (var.deploy_keycloak && var.deploy_developerhub && var.keycloak_bootstrap_user_enabled ? random_password.keycloak_bootstrap_password[0].result : "")
  bootstrap_password_temporary = var.keycloak_bootstrap_password_temporary

  depends_on = [
    module.gitops_template_processor,
    module.argocd_applications
  ]
}

resource "random_password" "keycloak_bootstrap_password" {
  count = var.deploy_keycloak && var.deploy_developerhub && var.keycloak_bootstrap_user_enabled && var.keycloak_bootstrap_password == "" ? 1 : 0

  length  = 24
  special = false
}
