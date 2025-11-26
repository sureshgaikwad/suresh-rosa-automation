# Create ArgoCD instance and RBAC - simple, no waiting
resource "null_resource" "create_argocd_instance" {
  count      = local.deploy_openshift_gitops ? 1 : 0
  depends_on = [time_sleep.wait_for_gitops_operator]

  provisioner "local-exec" {
    command = <<EOF
      oc login --username="${module.rosa_cluster_hcp.cluster_admin_username}" \
               --password="${module.rosa_cluster_hcp.cluster_admin_password}" \
               "${module.rosa_cluster_hcp.cluster_api_url}" \
               --insecure-skip-tls-verify

      # Create ArgoCD instance (idempotent)
      oc apply -f - <<ARGOCD_EOF
apiVersion: argoproj.io/v1alpha1
kind: ArgoCD
metadata:
  name: openshift-gitops
  namespace: openshift-gitops
spec:
  server:
    route:
      enabled: true
      tls:
        termination: reencrypt
  dex:
    openShiftOAuth: true
    resources:
      limits:
        cpu: 500m
        memory: 256Mi
      requests:
        cpu: 250m
        memory: 128Mi
  rbac:
    defaultPolicy: role:admin
    policy: |
      p, role:admin, applications, *, */*, allow
      p, role:admin, certificates, *, *, allow
      p, role:admin, clusters, *, *, allow
      p, role:admin, repositories, *, *, allow
      g, system:cluster-admins, role:admin
    scopes: '[groups]'
  controller:
    processors: {}
    resources:
      limits:
        cpu: 2000m
        memory: 2048Mi
      requests:
        cpu: 250m
        memory: 1024Mi
    sharding: {}
  redis:
    resources:
      limits:
        cpu: 500m
        memory: 256Mi
      requests:
        cpu: 250m
        memory: 128Mi
  ha:
    enabled: false
    resources:
      limits:
        cpu: 500m
        memory: 256Mi
      requests:
        cpu: 250m
        memory: 128Mi
  tls:
    ca: {}
  resourceExclusions: |
    - apiGroups:
      - tekton.dev
      clusters:
      - '*'
      kinds:
      - TaskRun
      - PipelineRun
ARGOCD_EOF

      # Create RBAC resources (idempotent)
      oc apply -f - <<RBAC_EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: argocd-application-controller-cluster-role
rules:
- apiGroups: ["*"]
  resources: ["*"]
  verbs: ["*"]
- nonResourceURLs: ["*"]
  verbs: ["*"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: argocd-application-controller-cluster-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: argocd-application-controller-cluster-role
subjects:
- kind: ServiceAccount
  name: openshift-gitops-argocd-application-controller
  namespace: openshift-gitops
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: argocd-server-cluster-role
rules:
- apiGroups: ["*"]
  resources: ["*"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["events", "pods", "pods/log"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: argocd-server-cluster-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: argocd-server-cluster-role
subjects:
- kind: ServiceAccount
  name: openshift-gitops-argocd-server
  namespace: openshift-gitops
RBAC_EOF
    EOF
  }

  triggers = {
    cluster_id = module.rosa_cluster_hcp.cluster_id
  }
}

# Minimal wait - just create applications, ArgoCD will sync when ready
resource "time_sleep" "wait_for_argocd" {
  count           = local.deploy_openshift_gitops ? 1 : 0
  depends_on      = [null_resource.create_argocd_instance[0]]
  create_duration = "5s"
}

# Create Vote Application
# Applications can be created immediately after ArgoCD RBAC is set up
resource "null_resource" "create_vote_application" {
  count      = var.deploy_vote_application && local.deploy_openshift_gitops ? 1 : 0
  depends_on = [null_resource.create_argocd_instance]

  provisioner "local-exec" {
    command = <<EOF
      # Login to cluster
      oc login --username="${module.rosa_cluster_hcp.cluster_admin_username}" --password="${module.rosa_cluster_hcp.cluster_admin_password}" "${module.rosa_cluster_hcp.cluster_api_url}" --insecure-skip-tls-verify

      # Create Vote Application
      oc apply -f - <<VOTE_APP_EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: vote-app
  namespace: openshift-gitops
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: ${var.gitops_repo_url}
    targetRevision: HEAD
    path: ${var.application_repo_path}
  destination:
    server: https://kubernetes.default.svc
    namespace: vote-app
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      allowEmpty: false
    syncOptions:
      - CreateNamespace=true
      - RespectIgnoreDifferences=true
      - ApplyOutOfSyncOnly=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
VOTE_APP_EOF

      echo "Vote application created"
    EOF
  }

  triggers = {
    cluster_id            = module.rosa_cluster_hcp.cluster_id
    admin_username        = module.rosa_cluster_hcp.cluster_admin_username
    admin_password        = module.rosa_cluster_hcp.cluster_admin_password
    api_url               = module.rosa_cluster_hcp.cluster_api_url
    gitops_repo_url       = var.gitops_repo_url
    application_repo_path = var.application_repo_path
    deploy_vote_app       = var.deploy_vote_application
  }
}
