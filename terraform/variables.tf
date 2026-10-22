variable "aws_region" {
  description = "AWS region to deploy EKS and supporting resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix for all created resources"
  type        = string
  default     = "secretless-oidc"
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for the EKS VPC"
  type        = string
  default     = "10.20.0.0/16"
}

variable "eks_cluster_version" {
  description = "Kubernetes version for AWS EKS"
  type        = string
  default     = "1.29"
}

variable "node_instance_types" {
  description = "EC2 instance types for EKS managed worker nodes"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "vault_address" {
  description = "Vault API endpoint used by the Terraform Vault provider"
  type        = string
  default     = "http://127.0.0.1:8200"
}

variable "vault_token" {
  description = "Bootstrap Vault token for initial OIDC configuration"
  type        = string
  sensitive   = true
  default     = "root"
}

variable "app_namespace" {
  description = "Kubernetes namespace for the secretless workload"
  type        = string
  default     = "app-ns"
}

variable "app_service_account" {
  description = "Kubernetes ServiceAccount name for the secretless workload"
  type        = string
  default     = "payment-processor"
}

variable "oidc_audience" {
  description = "Expected OIDC token audience claim (aud) verified by Vault"
  type        = string
  default     = "vault"
}
