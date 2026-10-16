output "role_arn" {
  value       = aws_iam_role.karpenter_controller.arn
  description = "IAM role ARN for Red Hat build of Karpenter (pass to cluster auto_node.role_arn)."
}

output "role_name" {
  value       = aws_iam_role.karpenter_controller.name
  description = "IAM role name for Red Hat build of Karpenter."
}

output "policy_arn" {
  value       = local.policy_arn
  description = "AWS managed ROSAKarpenterControllerPolicy ARN."
}
