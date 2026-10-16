################################################################################
# Red Hat build of Karpenter (AutoNode) IAM
#
# Controllers run in the ROSA HCP control plane (not as in-cluster pods).
# This module creates the controller IAM role with OIDC trust for
# system:serviceaccount:kube-system:karpenter and attaches the AWS managed
# ROSAKarpenterControllerPolicy.
#
# Docs: https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/html/cluster_administration/managing-compute-nodes-using-red-hat-build-of-karpenter
################################################################################

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  role_name = coalesce(
    var.role_name,
    substr("rosa-karpenter-controller-role-${var.cluster_name}", 0, 64)
  )
  oidc_provider = replace(var.oidc_endpoint_url, "https://", "")
  oidc_arn      = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${local.oidc_provider}"
  policy_arn    = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/ROSAKarpenterControllerPolicy"
}

data "aws_iam_policy_document" "karpenter_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider}:sub"
      values   = ["system:serviceaccount:kube-system:karpenter"]
    }
  }
}

resource "aws_iam_role" "karpenter_controller" {
  name                 = local.role_name
  path                 = var.path
  assume_role_policy   = data.aws_iam_policy_document.karpenter_trust.json
  permissions_boundary = var.permissions_boundary

  tags = merge(var.tags, {
    "red-hat-managed" = "true"
    "rosa-cluster"    = var.cluster_name
    "Purpose"         = "ROSA-Karpenter-AutoNode"
  })
}

resource "aws_iam_role_policy_attachment" "karpenter_controller" {
  role       = aws_iam_role.karpenter_controller.name
  policy_arn = local.policy_arn
}
