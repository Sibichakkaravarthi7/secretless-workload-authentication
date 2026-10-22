# KMS Key for Vault Auto-Unseal (Production Secretless Unsealing via AWS IRSA)
resource "aws_kms_key" "vault_unseal" {
  description             = "KMS Key for HashiCorp Vault Auto-Unseal on EKS"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_kms_alias" "vault_unseal" {
  name          = "alias/${var.project_name}-${var.environment}-vault-unseal"
  target_key_id = aws_kms_key.vault_unseal.key_id
}

# IAM Policy allowing Vault server pods to use KMS for auto-unseal via OIDC/IRSA
data "aws_iam_policy_document" "vault_kms_unseal" {
  statement {
    sid    = "VaultKMSUnseal"
    effect = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:DescribeKey"
    ]
    resources = [aws_kms_key.vault_unseal.arn]
  }
}

# Trust relationship federated with the EKS OIDC Provider for the Vault ServiceAccount
data "aws_iam_policy_document" "vault_irsa_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:sub"
      values   = ["system:serviceaccount:vault:vault"]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "vault_server_irsa" {
  name               = "${var.project_name}-${var.environment}-vault-irsa"
  assume_role_policy = data.aws_iam_policy_document.vault_irsa_trust.json
}

resource "aws_iam_role_policy" "vault_kms_unseal" {
  name   = "vault-kms-unseal-policy"
  role   = aws_iam_role.vault_server_irsa.id
  policy = data.aws_iam_policy_document.vault_kms_unseal.json
}
