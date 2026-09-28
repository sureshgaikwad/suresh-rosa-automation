locals {
  deploy_openshift_gitops = var.deploy_openshift_gitops

  # Fan-out: llmd → maas → ai
  deploy_rhoai_llmd   = var.deploy_rhoai_llmd
  deploy_rhoai_maas   = var.deploy_rhoai_maas || local.deploy_rhoai_llmd
  deploy_openshift_ai = var.deploy_openshift_ai || local.deploy_rhoai_maas

  deploy_nfd                             = local.deploy_openshift_ai ? true : var.deploy_nfd
  deploy_nvidia_gpu_operator             = local.deploy_openshift_ai ? true : var.deploy_nvidia_gpu_operator
  deploy_nfd_application                 = local.deploy_openshift_ai ? true : var.deploy_nfd_application
  deploy_nvidia_gpu_operator_application = local.deploy_openshift_ai ? true : var.deploy_nvidia_gpu_operator_application
  deploy_openshift_servicemesh           = var.deploy_openshift_servicemesh
  deploy_openshift_serverless            = local.deploy_openshift_ai ? true : var.deploy_openshift_serverless
  deploy_openshift_lightspeed            = var.deploy_openshift_lightspeed
  deploy_kueue_operator                  = local.deploy_openshift_ai ? true : var.deploy_kueue_operator
  deploy_jobset_operator                 = (local.deploy_openshift_ai || local.deploy_rhoai_maas) ? true : var.deploy_jobset_operator
  deploy_cert_manager_operator           = (local.deploy_openshift_ai || local.deploy_rhoai_maas) ? true : var.deploy_cert_manager_operator
  deploy_rhcl_operator                   = local.deploy_rhoai_maas
  deploy_leader_worker_set               = local.deploy_rhoai_maas
  deploy_custom_metrics_autoscaler       = local.deploy_rhoai_llmd
  # MaaS Observability dashboard (Perses) needs COO + OpenTelemetry
  deploy_cluster_observability_operator = local.deploy_rhoai_maas || var.deploy_cluster_observability_operator
  deploy_opentelemetry_operator         = local.deploy_rhoai_maas || var.deploy_opentelemetry_operator

  # Prefer live apps ingress domain over ROSA cluster_domain (missing apps.rosa. prefix).
  apps_ingress_domain = try(data.external.cluster_domain[0].result.domain, "")
  oauth_cluster_domain = (
    local.apps_ingress_domain != "" ? local.apps_ingress_domain : (
      var.cluster_domain != "" ? var.cluster_domain : ""
    )
  )

  rhoai_maas_hostname = var.rhoai_maas_hostname != "" ? var.rhoai_maas_hostname : (
    local.oauth_cluster_domain != "" ? "maas.${local.oauth_cluster_domain}" : "maas.example.com"
  )

  # Prefer IngressController default cert (ROSA primary-cert-bundle) over the
  # catalog placeholder cert-manager-ingress-cert which does not exist on HCP.
  rhoai_maas_tls_secret_name = var.rhoai_maas_tls_secret_name != "" ? var.rhoai_maas_tls_secret_name : (
    try(data.external.cluster_domain[0].result.tls_secret, "") != ""
    ? data.external.cluster_domain[0].result.tls_secret
    : "maas-gateway-tls"
  )

  rhoai_genai_component = var.rhoai_genai_backend == "ogx" ? "components/genai-ogx" : "components/llamastack"

  openshift_ai_kustomize_components = compact(concat(
    [local.rhoai_genai_component],
    local.deploy_rhoai_maas ? ["components/maas-enable"] : [],
  ))

  openshift_ai_maas_kustomize_components = compact(concat(
    var.deploy_rhoai_maas_sample_model && local.deploy_rhoai_maas ? ["components/sample-model"] : [],
  ))

  openshift_ai_llmd_kustomize_components = compact(concat(
    var.deploy_rhoai_llmd_keda && local.deploy_rhoai_llmd ? ["components/keda-autoscaling"] : [],
  ))

  # JSON6902 patches against params ConfigMaps — keeps cluster values out of git.
  rhoai_channel_patch = [{
    target = {
      kind = "Subscription"
      name = "rhods-operator"
    }
    patch = yamlencode([{
      op    = "replace"
      path  = "/spec/channel"
      value = var.rhoai_channel
    }])
  }]

  # Patch ConfigMap *and* Gateway. Argo CD applies kustomize.patches after
  # kustomize build, so replacements alone leave the Gateway hostname stale.
  rhoai_maas_params_patch = [
    {
      target = {
        kind      = "ConfigMap"
        name      = "rhoai-maas-params"
        namespace = "redhat-ods-applications"
      }
      patch = yamlencode([
        { op = "replace", path = "/data/maasHostname", value = local.rhoai_maas_hostname },
        { op = "replace", path = "/data/tlsSecretName", value = local.rhoai_maas_tls_secret_name },
        { op = "replace", path = "/data/modelName", value = var.rhoai_maas_model_name },
        { op = "replace", path = "/data/modelNamespace", value = var.rhoai_maas_model_namespace },
        { op = "replace", path = "/data/modelDisplayName", value = var.rhoai_maas_model_display_name },
        { op = "replace", path = "/data/modelOciUri", value = var.rhoai_maas_model_oci_uri },
        { op = "replace", path = "/data/vllmImage", value = var.rhoai_maas_vllm_image },
        { op = "replace", path = "/data/tokenRateLimit", value = var.rhoai_maas_token_rate_limit },
        { op = "replace", path = "/data/tokenRateWindow", value = var.rhoai_maas_token_rate_window },
        { op = "replace", path = "/data/postgresStorageSize", value = var.rhoai_maas_postgres_storage_size },
        { op = "replace", path = "/data/postgresImage", value = var.rhoai_maas_postgres_image },
      ])
    },
    {
      target = {
        group     = "gateway.networking.k8s.io"
        kind      = "Gateway"
        name      = "maas-default-gateway"
        namespace = "openshift-ingress"
      }
      patch = yamlencode([
        { op = "replace", path = "/spec/listeners/0/hostname", value = local.rhoai_maas_hostname },
        { op = "replace", path = "/spec/listeners/0/tls/certificateRefs/0/name", value = local.rhoai_maas_tls_secret_name },
      ])
    },
  ]

  rhoai_llmd_params_patch = [{
    target = {
      kind      = "ConfigMap"
      name      = "rhoai-llmd-params"
      namespace = var.rhoai_maas_model_namespace
    }
    patch = yamlencode([
      { op = "replace", path = "/data/modelName", value = var.rhoai_llmd_model_name },
      { op = "replace", path = "/data/modelNamespace", value = var.rhoai_maas_model_namespace },
      { op = "replace", path = "/data/modelDisplayName", value = var.rhoai_llmd_model_name },
      { op = "replace", path = "/data/modelOciUri", value = var.rhoai_llmd_model_oci_uri },
      { op = "replace", path = "/data/vllmImage", value = var.rhoai_maas_vllm_image },
      { op = "replace", path = "/data/kedaMinReplicas", value = var.rhoai_llmd_keda_min_replicas },
      { op = "replace", path = "/data/kedaMaxReplicas", value = var.rhoai_llmd_keda_max_replicas },
      { op = "replace", path = "/data/kedaThreshold", value = var.rhoai_llmd_keda_threshold },
    ])
  }]

  catalog_repo = var.gitops_repo_url

  argocd_applications = {
    vote-app = {
      enabled              = var.deploy_vote_application && local.deploy_openshift_gitops
      path                 = var.application_repo_path
      namespace            = "vote-app"
      repo_url             = var.gitops_repo_url
      create_namespace     = true
      dependency_weight    = 1
      kustomize_components = []
      kustomize_patches    = []
    }
    cert-manager-operator = {
      enabled              = local.deploy_cert_manager_operator && local.deploy_openshift_gitops
      path                 = "operators/cert-manager-operator"
      namespace            = "cert-manager-operator"
      repo_url             = local.catalog_repo
      create_namespace     = true
      dependency_weight    = 1
      kustomize_components = []
      kustomize_patches    = []
    }
    rhcl-operator = {
      enabled              = local.deploy_rhcl_operator && local.deploy_openshift_gitops
      path                 = "operators/rhcl-operator"
      namespace            = "openshift-operators"
      repo_url             = local.catalog_repo
      create_namespace     = true
      dependency_weight    = 1
      kustomize_components = []
      kustomize_patches    = []
    }
    openshift-ai-operator = {
      enabled              = local.deploy_openshift_ai && local.deploy_openshift_gitops
      path                 = "operators/openshift-ai"
      namespace            = "redhat-ods-operator"
      repo_url             = local.catalog_repo
      create_namespace     = true
      dependency_weight    = local.deploy_rhoai_maas ? 3 : 2
      kustomize_components = local.openshift_ai_kustomize_components
      kustomize_patches    = local.rhoai_channel_patch
    }
    openshift-serverless-operator = {
      enabled              = local.deploy_openshift_serverless && local.deploy_openshift_gitops
      path                 = "operators/openshift-serverless"
      namespace            = "openshift-serverless"
      repo_url             = local.catalog_repo
      create_namespace     = true
      dependency_weight    = 2
      kustomize_components = []
      kustomize_patches    = []
    }
    openshift-servicemesh-operator = {
      enabled              = local.deploy_openshift_servicemesh && local.deploy_openshift_gitops
      path                 = "operators/openshift-servicemesh"
      namespace            = "istio-system"
      repo_url             = local.catalog_repo
      create_namespace     = true
      dependency_weight    = 2
      kustomize_components = []
      kustomize_patches    = []
    }
    openshift-lightspeed-operator = {
      enabled              = local.deploy_openshift_lightspeed && local.deploy_openshift_gitops
      path                 = "operators/openshift-lightspeed"
      namespace            = "openshift-lightspeed"
      repo_url             = local.catalog_repo
      create_namespace     = true
      dependency_weight    = 2
      kustomize_components = []
      kustomize_patches    = []
    }
    nfd-gitops = {
      enabled              = local.deploy_nfd_application && local.deploy_openshift_gitops
      path                 = "operators/node-file-discovery-operator"
      namespace            = "openshift-nfd"
      repo_url             = local.catalog_repo
      create_namespace     = true
      dependency_weight    = 2
      kustomize_components = []
      kustomize_patches    = []
    }
    nvidia-gpu-operator-gitops = {
      enabled              = local.deploy_nvidia_gpu_operator_application && local.deploy_openshift_gitops
      path                 = "operators/nvidia-gpu-operator"
      namespace            = "nvidia-gpu-operator"
      repo_url             = local.catalog_repo
      create_namespace     = true
      dependency_weight    = 3
      kustomize_components = []
      kustomize_patches    = []
    }
    authorino-operator = {
      enabled              = var.deploy_authorino_operator && local.deploy_openshift_gitops
      path                 = "operators/authorino-operator"
      namespace            = "authorino-operator"
      repo_url             = local.catalog_repo
      create_namespace     = true
      dependency_weight    = 2
      kustomize_components = []
      kustomize_patches    = []
    }
    kueue-operator = {
      enabled              = local.deploy_kueue_operator && local.deploy_openshift_gitops
      path                 = "operators/kueue-operator"
      namespace            = "openshift-kueue-operator"
      repo_url             = local.catalog_repo
      create_namespace     = true
      dependency_weight    = 2
      kustomize_components = []
      kustomize_patches    = []
    }
    jobset-operator = {
      enabled              = local.deploy_jobset_operator && local.deploy_openshift_gitops
      path                 = "operators/jobset-operator"
      namespace            = "openshift-jobset-operator"
      repo_url             = local.catalog_repo
      create_namespace     = true
      dependency_weight    = 2
      kustomize_components = []
      kustomize_patches    = []
    }
    leader-worker-set = {
      enabled              = local.deploy_leader_worker_set && local.deploy_openshift_gitops
      path                 = "operators/leader-worker-set"
      namespace            = "openshift-lws-operator"
      repo_url             = local.catalog_repo
      create_namespace     = true
      dependency_weight    = 2
      kustomize_components = []
      kustomize_patches    = []
    }
    cluster-observability-operator = {
      enabled              = local.deploy_cluster_observability_operator && local.deploy_openshift_gitops
      path                 = "operators/cluster-observability-operator"
      namespace            = "openshift-cluster-observability-operator"
      repo_url             = local.catalog_repo
      create_namespace     = true
      dependency_weight    = 1
      kustomize_components = []
      kustomize_patches    = []
    }
    opentelemetry-operator = {
      enabled              = local.deploy_opentelemetry_operator && local.deploy_openshift_gitops
      path                 = "operators/opentelemetry-operator"
      namespace            = "openshift-opentelemetry-operator"
      repo_url             = local.catalog_repo
      create_namespace     = true
      dependency_weight    = 1
      kustomize_components = []
      kustomize_patches    = []
    }
    openshift-ai-maas = {
      enabled              = local.deploy_rhoai_maas && local.deploy_openshift_gitops
      path                 = "operators/openshift-ai-maas"
      namespace            = "redhat-ods-applications"
      repo_url             = local.catalog_repo
      create_namespace     = true
      dependency_weight    = 2
      kustomize_components = local.openshift_ai_maas_kustomize_components
      kustomize_patches    = local.rhoai_maas_params_patch
    }
    custom-metrics-autoscaler = {
      enabled              = local.deploy_custom_metrics_autoscaler && local.deploy_openshift_gitops
      path                 = "operators/custom-metrics-autoscaler"
      namespace            = "openshift-keda"
      repo_url             = local.catalog_repo
      create_namespace     = true
      dependency_weight    = 4
      kustomize_components = []
      kustomize_patches    = []
    }
    openshift-ai-llmd = {
      enabled              = local.deploy_rhoai_llmd && local.deploy_openshift_gitops
      path                 = "operators/openshift-ai-llmd"
      namespace            = var.rhoai_maas_model_namespace
      repo_url             = local.catalog_repo
      create_namespace     = true
      dependency_weight    = 5
      kustomize_components = local.openshift_ai_llmd_kustomize_components
      kustomize_patches    = local.rhoai_llmd_params_patch
    }
    ai-model = {
      enabled              = var.deploy_ai_model && local.deploy_openshift_gitops
      path                 = "ai-models/qwen"
      namespace            = "models"
      repo_url             = var.gitops_repo_url
      create_namespace     = true
      dependency_weight    = 4
      kustomize_components = []
      kustomize_patches    = []
    }
    keycloak-operator = {
      enabled              = var.deploy_keycloak && local.deploy_openshift_gitops
      path                 = "operators/keycloak/base"
      namespace            = "rhbk"
      repo_url             = local.catalog_repo
      create_namespace     = true
      dependency_weight    = 2
      kustomize_components = []
      kustomize_patches    = []
    }
    developer-hub-operator = {
      enabled              = var.deploy_developerhub && local.deploy_openshift_gitops
      path                 = "operators/developer-hub"
      namespace            = "demo-project"
      repo_url             = local.catalog_repo
      create_namespace     = true
      dependency_weight    = 3
      kustomize_components = []
      kustomize_patches    = []
    }
    openshift-devspaces-operator = {
      enabled              = var.deploy_openshift_devspaces && local.deploy_openshift_gitops
      path                 = "operators/openshift-devspaces"
      namespace            = "openshift-devspaces"
      repo_url             = local.catalog_repo
      create_namespace     = true
      dependency_weight    = 2
      kustomize_components = []
      kustomize_patches    = []
    }
    openshift-virtualization-operator = {
      enabled              = var.deploy_openshift_virtualization && local.deploy_openshift_gitops
      path                 = "operators/openshift-virtualization"
      namespace            = "openshift-cnv"
      repo_url             = local.catalog_repo
      create_namespace     = true
      dependency_weight    = 2
      kustomize_components = []
      kustomize_patches    = []
    }
    web-terminal-operator = {
      enabled              = var.deploy_web_terminal && local.deploy_openshift_gitops
      path                 = "operators/web-terminal"
      namespace            = "openshift-terminal"
      repo_url             = local.catalog_repo
      create_namespace     = true
      dependency_weight    = 2
      kustomize_components = []
      kustomize_patches    = []
    }
    acm-operator = {
      enabled              = var.deploy_advance_cluster_management && local.deploy_openshift_gitops
      path                 = "operators/advanced-cluster-management"
      namespace            = "open-cluster-management"
      repo_url             = local.catalog_repo
      create_namespace     = true
      dependency_weight    = 2
      kustomize_components = []
      kustomize_patches    = []
    }
  }

  enabled_argocd_applications = {
    for k, v in local.argocd_applications : k => v if v.enabled
  }

  devhub_redirect_uris = var.deploy_developerhub && var.deploy_keycloak ? [
    "https://backstage-developer-hub-demo-project.${local.oauth_cluster_domain}/*",
    "https://backstage-developer-hub-demo-project.${local.oauth_cluster_domain}/api/auth/oidc/handler/frame"
  ] : []

  devhub_web_origins = var.deploy_developerhub && var.deploy_keycloak ? [
    "https://backstage-developer-hub-demo-project.${local.oauth_cluster_domain}"
  ] : []
}
