output "aws_region" {
  description = "AWS Region"
  value       = var.aws_region
}

output "cluster_name" {
  description = "EKS Cluster Name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS Control Plane Endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_oidc_issuer_url" {
  description = "The OIDC Discovery URL of the EKS Cluster used by Vault"
  value       = module.eks.cluster_oidc_issuer_url
}

output "oidc_provider_arn" {
  description = "IAM OIDC Provider ARN for EKS"
  value       = module.eks.oidc_provider_arn
}

output "vault_kms_key_arn" {
  description = "KMS Key ARN created for Vault Auto-Unseal"
  value       = aws_kms_key.vault_unseal.arn
}

output "expected_jwt_subject" {
  description = "Bound OIDC subject claim required by Vault"
  value       = "system:serviceaccount:${var.app_namespace}:${var.app_service_account}"
}
