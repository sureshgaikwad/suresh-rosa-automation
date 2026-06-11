##############################################################
# OpenShift Features and Dependencies Logic
##############################################################

locals {
  # GitOps enablement - computed based on input variable
  deploy_openshift_gitops = var.deploy_openshift_gitops

  # Dependency logic: When OpenShift AI is enabled, automatically enable prerequisite operators
  deploy_nfd                             = var.deploy_openshift_ai ? true : var.deploy_nfd
  deploy_nvidia_gpu_operator             = var.deploy_openshift_ai ? true : var.deploy_nvidia_gpu_operator
  deploy_nfd_application                 = var.deploy_openshift_ai ? true : var.deploy_nfd_application
  deploy_nvidia_gpu_operator_application = var.deploy_openshift_ai ? true : var.deploy_nvidia_gpu_operator_application
  deploy_openshift_servicemesh           = var.deploy_openshift_servicemesh # RHOAI 3.x auto-installs Service Mesh 3 via OLM dependency
  deploy_openshift_serverless            = var.deploy_openshift_ai ? true : var.deploy_openshift_serverless
  # Keep Lightspeed as an explicit opt-in feature. Do not force-enable it with OpenShift AI.
  deploy_openshift_lightspeed  = var.deploy_openshift_lightspeed
  deploy_kueue_operator        = var.deploy_openshift_ai ? true : var.deploy_kueue_operator
  deploy_jobset_operator       = var.deploy_openshift_ai ? true : var.deploy_jobset_operator
  deploy_cert_manager_operator = var.deploy_openshift_ai ? true : var.deploy_cert_manager_operator
}

##############################################################
# ArgoCD Applications Map (Data-Driven Pattern)
##############################################################

locals {
  # Define all ArgoCD applications in a map for data-driven deployment
  # This replaces the individual null_resource blocks in argocd-applications.tf
  # and argocd-operator-applications.tf
  argocd_applications = {
    # Vote Application
    vote-app = {
      enabled           = var.deploy_vote_application && local.deploy_openshift_gitops
      path              = var.application_repo_path
      namespace         = "vote-app"
      repo_url          = var.gitops_repo_url
      create_namespace  = true
      dependency_weight = 1 # Base applications
    }

    # OpenShift AI Operator
    openshift-ai-operator = {
      enabled           = var.deploy_openshift_ai && local.deploy_openshift_gitops
      path              = "operators/openshift-ai"
      namespace         = "redhat-ods-operator"
      repo_url          = var.gitops_repo_url
      create_namespace  = true
      dependency_weight = 2 # Operators
    }

    # OpenShift Serverless Operator
    openshift-serverless-operator = {
      enabled           = local.deploy_openshift_serverless && local.deploy_openshift_gitops
      path              = "operators/openshift-serverless"
      namespace         = "openshift-serverless"
      repo_url          = var.gitops_repo_url
      create_namespace  = true
      dependency_weight = 2
    }

    # OpenShift Service Mesh Operator
    openshift-servicemesh-operator = {
      enabled           = local.deploy_openshift_servicemesh && local.deploy_openshift_gitops
      path              = "operators/openshift-servicemesh"
      namespace         = "istio-system"
      repo_url          = var.gitops_repo_url
      create_namespace  = true
      dependency_weight = 2
    }

    # OpenShift Lightspeed Operator
    openshift-lightspeed-operator = {
      enabled           = local.deploy_openshift_lightspeed && local.deploy_openshift_gitops
      path              = "operators/openshift-lightspeed"
      namespace         = "openshift-lightspeed"
      repo_url          = "https://github.com/sureshgaikwad/gitops-catalog"
      create_namespace  = true
      dependency_weight = 2
    }

    # Node Feature Discovery Operator (GitOps Catalog)
    nfd-gitops = {
      enabled           = local.deploy_nfd_application && local.deploy_openshift_gitops
      path              = "operators/node-file-discovery-operator"
      namespace         = "openshift-nfd"
      repo_url          = "https://github.com/sureshgaikwad/gitops-catalog"
      create_namespace  = true
      dependency_weight = 2
    }

    # NVIDIA GPU Operator (GitOps Catalog)
    nvidia-gpu-operator-gitops = {
      enabled           = local.deploy_nvidia_gpu_operator_application && local.deploy_openshift_gitops
      path              = "operators/nvidia-gpu-operator"
      namespace         = "nvidia-gpu-operator"
      repo_url          = "https://github.com/sureshgaikwad/gitops-catalog"
      create_namespace  = true
      dependency_weight = 3 # Depends on NFD
    }

    # Authorino Operator
    authorino-operator = {
      enabled           = var.deploy_authorino_operator && local.deploy_openshift_gitops
      path              = "operators/authorino-operator"
      namespace         = "authorino-operator"
      repo_url          = "https://github.com/sureshgaikwad/gitops-catalog"
      create_namespace  = true
      dependency_weight = 2
    }

    # cert-manager Operator (required by JobSet operator for webhook certificates)
    cert-manager-operator = {
      enabled           = local.deploy_cert_manager_operator && local.deploy_openshift_gitops
      path              = "operators/cert-manager-operator"
      namespace         = "cert-manager-operator"
      repo_url          = "https://github.com/sureshgaikwad/gitops-catalog"
      create_namespace  = true
      dependency_weight = 1
    }

    # Kueue Operator (required by OpenShift AI for job queuing)
    kueue-operator = {
      enabled           = local.deploy_kueue_operator && local.deploy_openshift_gitops
      path              = "operators/kueue-operator"
      namespace         = "openshift-kueue-operator"
      repo_url          = "https://github.com/sureshgaikwad/gitops-catalog"
      create_namespace  = true
      dependency_weight = 2
    }

    # JobSet Operator (required by OpenShift AI Trainer component)
    jobset-operator = {
      enabled           = local.deploy_jobset_operator && local.deploy_openshift_gitops
      path              = "operators/jobset-operator"
      namespace         = "openshift-jobset-operator"
      repo_url          = "https://github.com/sureshgaikwad/gitops-catalog"
      create_namespace  = true
      dependency_weight = 2
    }

    # AI Model
    ai-model = {
      enabled           = var.deploy_ai_model && local.deploy_openshift_gitops
      path              = "ai-models/qwen"
      namespace         = "models"
      repo_url          = var.gitops_repo_url
      create_namespace  = true
      dependency_weight = 4 # Depends on OpenShift AI
    }

    # Keycloak Operator (path in gitops-catalog is operators/keycloak/base for Kustomize)
    keycloak-operator = {
      enabled           = var.deploy_keycloak && local.deploy_openshift_gitops
      path              = "operators/keycloak/base"
      namespace         = "rhbk"
      repo_url          = "https://github.com/sureshgaikwad/gitops-catalog"
      create_namespace  = true
      dependency_weight = 2
    }

    # Developer Hub instance resources (Backstage CR, PVC, configmaps, RBAC)
    developer-hub-operator = {
      enabled           = var.deploy_developerhub && local.deploy_openshift_gitops
      path              = "operators/developer-hub"
      namespace         = "demo-project"
      repo_url          = "https://github.com/sureshgaikwad/gitops-catalog"
      create_namespace  = true
      dependency_weight = 3 # Depends on operator availability and Keycloak auth setup
    }

    # OpenShift Dev Spaces Operator
    openshift-devspaces-operator = {
      enabled           = var.deploy_openshift_devspaces && local.deploy_openshift_gitops
      path              = "operators/openshift-devspaces"
      namespace         = "openshift-devspaces"
      repo_url          = "https://github.com/sureshgaikwad/gitops-catalog"
      create_namespace  = true
      dependency_weight = 2
    }

    # OpenShift Virtualization Operator
    openshift-virtualization-operator = {
      enabled           = var.deploy_openshift_virtualization && local.deploy_openshift_gitops
      path              = "operators/openshift-virtualization"
      namespace         = "openshift-cnv"
      repo_url          = "https://github.com/sureshgaikwad/gitops-catalog"
      create_namespace  = true
      dependency_weight = 2
    }

    # Web Terminal Operator
    web-terminal-operator = {
      enabled           = var.deploy_web_terminal && local.deploy_openshift_gitops
      path              = "operators/web-terminal"
      namespace         = "openshift-terminal"
      repo_url          = "https://github.com/sureshgaikwad/gitops-catalog"
      create_namespace  = true
      dependency_weight = 2
    }

    # Advanced Cluster Management Operator
    acm-operator = {
      enabled           = var.deploy_advance_cluster_management && local.deploy_openshift_gitops
      path              = "operators/advanced-cluster-management"
      namespace         = "open-cluster-management"
      repo_url          = "https://github.com/sureshgaikwad/gitops-catalog"
      create_namespace  = true
      dependency_weight = 2
    }
  }

  # Filter to only enabled applications
  enabled_argocd_applications = {
    for k, v in local.argocd_applications : k => v if v.enabled
  }
}

##############################################################
# Developer Hub / Keycloak OAuth Configuration
##############################################################

locals {
  # Compute cluster domain for OAuth redirect URIs (from external data source)
  oauth_cluster_domain = try(data.external.cluster_domain[0].result.domain, "")

  # Compute OAuth redirect URIs for Developer Hub
  devhub_redirect_uris = var.deploy_developerhub && var.deploy_keycloak ? [
    "https://backstage-developer-hub-demo-project.${local.oauth_cluster_domain}/*",
    "https://backstage-developer-hub-demo-project.${local.oauth_cluster_domain}/api/auth/oidc/handler/frame"
  ] : []

  devhub_web_origins = var.deploy_developerhub && var.deploy_keycloak ? [
    "https://backstage-developer-hub-demo-project.${local.oauth_cluster_domain}"
  ] : []
}
