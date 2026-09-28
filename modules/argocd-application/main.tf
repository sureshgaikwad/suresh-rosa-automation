################################################################################
# ArgoCD Application Module
#
# Creates an ArgoCD Application resource in a reusable way.
# Supports optional kustomize/helm parameterization and sync-wave ordering.
################################################################################

locals {
  metadata_annotations = merge(
    var.dependency_weight != null ? {
      "argocd.argoproj.io/sync-wave" = tostring(var.dependency_weight)
    } : {},
  )

  has_kustomize = (
    length(var.kustomize_components) > 0 ||
    length(var.kustomize_patches) > 0 ||
    length(var.kustomize_images) > 0 ||
    length(var.kustomize_common_annotations) > 0
  )

  has_helm = var.use_helm || length(var.helm_parameters) > 0 || var.helm_values != ""

  kustomize_block = local.has_kustomize ? merge(
    length(var.kustomize_components) > 0 ? { components = var.kustomize_components } : {},
    length(var.kustomize_images) > 0 ? { images = var.kustomize_images } : {},
    length(var.kustomize_common_annotations) > 0 ? { commonAnnotations = var.kustomize_common_annotations } : {},
    length(var.kustomize_patches) > 0 ? {
      patches = [
        for p in var.kustomize_patches : merge(
          p.target != null ? {
            target = {
              for k, v in {
                group              = try(p.target.group, null)
                version            = try(p.target.version, null)
                kind               = try(p.target.kind, null)
                name               = try(p.target.name, null)
                namespace          = try(p.target.namespace, null)
                labelSelector      = try(p.target.label_selector, null)
                annotationSelector = try(p.target.annotation_selector, null)
              } : k => v if v != null
            }
          } : {},
          p.patch != null ? { patch = p.patch } : {},
          p.path != null ? { path = p.path } : {},
        )
      ]
    } : {},
  ) : null

  helm_block = local.has_helm ? merge(
    length(var.helm_parameters) > 0 ? {
      parameters = [for p in var.helm_parameters : { name = p.name, value = p.value }]
    } : {},
    var.helm_values != "" ? { values = var.helm_values } : {},
  ) : null

  sync_options = concat(
    [
      "CreateNamespace=${var.create_namespace}",
      "RespectIgnoreDifferences=true",
      "ApplyOutOfSyncOnly=true",
    ],
    var.sync_options,
  )

  application_manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = merge(
      {
        name       = var.application_name
        namespace  = var.argocd_namespace
        finalizers = ["resources-finalizer.argocd.argoproj.io"]
      },
      length(local.metadata_annotations) > 0 ? { annotations = local.metadata_annotations } : {},
    )
    spec = {
      project = var.project
      source = merge(
        {
          repoURL        = var.repo_url
          targetRevision = var.target_revision
          path           = var.path
        },
        local.kustomize_block != null ? { kustomize = local.kustomize_block } : {},
        local.helm_block != null ? { helm = local.helm_block } : {},
      )
      destination = {
        server    = var.destination_server
        namespace = var.destination_namespace
      }
      syncPolicy = {
        automated = {
          prune      = var.auto_prune
          selfHeal   = var.self_heal
          allowEmpty = false
        }
        syncOptions = local.sync_options
        retry = {
          limit = var.retry_limit
          backoff = {
            duration    = "5s"
            factor      = 2
            maxDuration = "3m"
          }
        }
      }
    }
  }
}

resource "null_resource" "argocd_application" {
  count = var.enabled ? 1 : 0

  provisioner "local-exec" {
    environment = {
      OC_USERNAME = var.cluster_admin_username
      OC_PASSWORD = var.cluster_admin_password
      OC_API_URL  = var.cluster_api_url
      # Base64 avoids shell/env mangling of newlines inside kustomize patch strings.
      APP_JSON_B64 = base64encode(jsonencode(local.application_manifest))
    }

    command = <<-EOT
      #!/bin/bash
      set -euo pipefail
      unset KUBECONFIG

      if [ -f "${path.root}/scripts/oc-login.sh" ]; then
        source "${path.root}/scripts/oc-login.sh"
      elif [ -f "${path.root}/../../scripts/oc-login.sh" ]; then
        source "${path.root}/../../scripts/oc-login.sh"
      else
        echo "oc-login.sh not found relative to ${path.root}" >&2
        exit 1
      fi

      TMP_APP="$(mktemp)"
      printf '%s' "$APP_JSON_B64" | base64 -d > "$TMP_APP"
      oc apply --kubeconfig="$KUBECONFIG" -f "$TMP_APP"
      rm -f "$TMP_APP" "$KUBECONFIG"
      echo "ArgoCD application '${var.application_name}' created"
    EOT
  }

  triggers = {
    cluster_id       = var.cluster_id
    application_name = var.application_name
    repo_url         = var.repo_url
    path             = var.path
    manifest_hash    = sha256(jsonencode(local.application_manifest))
  }
}
