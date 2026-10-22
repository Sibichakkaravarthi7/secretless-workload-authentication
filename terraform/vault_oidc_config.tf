# ------------------------------------------------------------------------------
# 1. Enable KV-v2 Secret Engine & Seed Sample Workload Secrets
# ------------------------------------------------------------------------------
resource "vault_mount" "kvv2" {
  path        = "secret"
  type        = "kv"
  options     = { version = "2" }
  description = "KV v2 secret engine for EKS workloads"
}

resource "vault_kv_secret_v2" "payment_processor_config" {
  mount               = vault_mount.kvv2.path
  name                = "payment-processor/config"
  delete_all_versions = true

  data_json = jsonencode({
    DB_HOST          = "prod-payments-cluster.cluster-ro-abc123xyz.us-east-1.rds.amazonaws.com"
    DB_USER          = "svc_payment_app"
    DB_PASSWORD      = "vlt_dyn_9f8e7d6c5b4a3210_secretless"
    STRIPE_API_KEY   = "sk_test_51SecretlessOIDCVaultDemoKey998877"
    WEBHOOK_HMAC_KEY = "whsec_oidc_verified_ephemeral_secret_2026"
  })
}

# ------------------------------------------------------------------------------
# 2. Least-Privilege Vault Policy for the Workload
# ------------------------------------------------------------------------------
resource "vault_policy" "payment_processor" {
  name = "${var.app_service_account}-policy"

  policy = <<-EOT
    # Allow read access ONLY to the payment-processor secret path
    path "secret/data/payment-processor/*" {
      capabilities = ["read"]
    }

    path "secret/metadata/payment-processor/*" {
      capabilities = ["list"]
    }
  EOT
}

# ------------------------------------------------------------------------------
# 3. Enable Vault JWT/OIDC Auth Backend Validating Against AWS EKS OIDC Issuer
# ------------------------------------------------------------------------------
resource "vault_jwt_auth_backend" "eks_oidc" {
  description        = "AWS EKS OIDC Workload Identity Auth Backend"
  path               = "jwt"
  type               = "jwt"
  oidc_discovery_url = module.eks.cluster_oidc_issuer_url
  bound_issuer       = module.eks.cluster_oidc_issuer_url
}

# ------------------------------------------------------------------------------
# 4. Create Bound JWT Role Mapped Strictly to K8s Namespace + ServiceAccount
# ------------------------------------------------------------------------------
resource "vault_jwt_auth_backend_role" "payment_processor" {
  backend         = vault_jwt_auth_backend.eks_oidc.path
  role_name       = var.app_service_account
  role_type       = "jwt"
  bound_audiences = [var.oidc_audience]
  user_claim      = "sub"

  # Cryptographically bind to the exact Kubernetes ServiceAccount subject
  bound_subject = "system:serviceaccount:${var.app_namespace}:${var.app_service_account}"

  token_policies = [vault_policy.payment_processor.name]
  token_ttl      = 900  # 15 minutes
  token_max_ttl  = 3600 # 1 hour
}
