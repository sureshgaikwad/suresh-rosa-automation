################################################################################
# OpenShift GitOps Module
#
# Installs and configures OpenShift GitOps (ArgoCD) operator on a ROSA cluster.
# This module handles:
# - Cluster readiness checks
# - GitOps operator installation
# - ArgoCD instance creation
# - RBAC configuration
################################################################################

################################################################################
# Wait for cluster to be ready
################################################################################

resource "time_sleep" "wait_for_cluster" {
  count           = var.enabled ? 1 : 0
  create_duration = var.cluster_wait_duration
}

resource "null_resource" "wait_for_cluster_and_nodes" {
  count      = var.enabled ? 1 : 0
  depends_on = [time_sleep.wait_for_cluster]

  provisioner "local-exec" {
    command = <<-EOT
      #!/bin/bash
      set -e
      echo "Checking cluster and node readiness..."

      export OC_USERNAME="${var.cluster_admin_username}"
      export OC_PASSWORD="${var.cluster_admin_password}"
      export OC_API_URL="${var.cluster_api_url}"
      source ${path.root}/scripts/oc-login.sh
      
      echo "Waiting for nodes to be ready..."
      wait_start=$(date +%s)
      while true; do
        current_time=$(date +%s)
        elapsed=$((current_time - wait_start))
        
        if [ $elapsed -ge ${var.node_wait_timeout} ]; then
          echo "WARNING: Timeout waiting for nodes, continuing..."
          break
        fi
        
        ready_nodes=$(oc get nodes --no-headers 2>/dev/null | grep -c " Ready " || echo "0")
        if [ "$ready_nodes" -gt 0 ]; then
          echo "Node is available!"
          break
        fi
        
        sleep 30
      done
      
      echo "Waiting for marketplace..."
      wait_start=$(date +%s)
      while true; do
        current_time=$(date +%s)
        elapsed=$((current_time - wait_start))
        
        if [ $elapsed -ge 120 ]; then
          echo "WARNING: Timeout waiting for marketplace, continuing..."
          break
        fi
        
        if oc get packagemanifest openshift-gitops-operator >/dev/null 2>&1; then
          echo "Marketplace ready!"
          break
        fi
        
        sleep 15
      done
    EOT
  }

  triggers = {
    cluster_id = var.cluster_id
  }
}

################################################################################
# Install GitOps Operator
################################################################################

resource "null_resource" "install_gitops_operator" {
  count      = var.enabled ? 1 : 0
  depends_on = [null_resource.wait_for_cluster_and_nodes]

  provisioner "local-exec" {
    command = <<-EOT
      #!/bin/bash
      set -e

      export OC_USERNAME="${var.cluster_admin_username}"
      export OC_PASSWORD="${var.cluster_admin_password}"
      export OC_API_URL="${var.cluster_api_url}"
      source ${path.root}/scripts/oc-login.sh

      # Create namespace
      cat <<EOF | oc apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-gitops
  labels:
    openshift.io/cluster-monitoring: "true"
EOF

      # Create OperatorGroup
      cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-gitops-operator-group
  namespace: openshift-gitops
spec: {}
EOF

      # Create Subscription
      cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-gitops-operator
  namespace: openshift-gitops
spec:
  channel: ${var.gitops_channel}
  installPlanApproval: Automatic
  name: openshift-gitops-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

      echo "GitOps operator installation initiated"
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      #!/bin/bash
      set +e
      timeout 30 oc login --username="${self.triggers.admin_username}" \
                          --password="${self.triggers.admin_password}" \
                          "${self.triggers.api_url}" \
                          --insecure-skip-tls-verify 2>/dev/null || exit 0
      
      oc delete subscription openshift-gitops-operator -n openshift-gitops --ignore-not-found=true --timeout=20s 2>/dev/null || true
      oc delete operatorgroup openshift-gitops-operator-group -n openshift-gitops --ignore-not-found=true --timeout=20s 2>/dev/null || true
      oc patch namespace openshift-gitops -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
      oc delete namespace openshift-gitops --ignore-not-found=true --timeout=30s 2>/dev/null || true
      exit 0
    EOT
  }

  triggers = {
    cluster_id     = var.cluster_id
    admin_username = var.cluster_admin_username
    admin_password = var.cluster_admin_password
    api_url        = var.cluster_api_url
  }
}

resource "time_sleep" "wait_for_gitops_operator" {
  count           = var.enabled ? 1 : 0
  depends_on      = [null_resource.install_gitops_operator]
  create_duration = var.operator_wait_duration
}

################################################################################
# Create ArgoCD Instance
################################################################################

resource "null_resource" "create_argocd_instance" {
  count      = var.enabled && var.create_argocd_instance ? 1 : 0
  depends_on = [time_sleep.wait_for_gitops_operator]

  provisioner "local-exec" {
    command = <<-EOT
      #!/bin/bash
      set -e

      export OC_USERNAME="${var.cluster_admin_username}"
      export OC_PASSWORD="${var.cluster_admin_password}"
      export OC_API_URL="${var.cluster_api_url}"
      source ${path.root}/scripts/oc-login.sh

      # Create ArgoCD instance
      cat <<EOF | oc apply --kubeconfig=$KUBECONFIG -f -
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
  redis:
    resources:
      limits:
        cpu: 500m
        memory: 256Mi
      requests:
        cpu: 250m
        memory: 128Mi
  repo:
    resources:
      limits:
        cpu: "2"
        memory: 2Gi
      requests:
        cpu: 500m
        memory: 512Mi
  ha:
    enabled: false
EOF

      sleep 30

      # Create ClusterRole for ArgoCD
      cat <<EOF | oc apply --kubeconfig=$KUBECONFIG -f -
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
EOF

      # Create ClusterRoleBinding
      cat <<EOF | oc apply --kubeconfig=$KUBECONFIG -f -
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
EOF

      rm -f $KUBECONFIG
      echo "ArgoCD instance and RBAC configured"
    EOT
  }

  triggers = {
    cluster_id = var.cluster_id
  }
}

resource "time_sleep" "wait_for_argocd" {
  count           = var.enabled && var.create_argocd_instance ? 1 : 0
  depends_on      = [null_resource.create_argocd_instance]
  create_duration = var.argocd_wait_duration
}
