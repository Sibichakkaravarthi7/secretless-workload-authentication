#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Standalone Vault + AWS EKS OIDC Setup Script
# Configures Vault JWT/OIDC Auth against the AWS EKS OIDC Discovery URL
# ==============================================================================

CLUSTER_NAME="${CLUSTER_NAME:-secretless-oidc-dev-eks}"
AWS_REGION="${AWS_REGION:-us-east-1}"
APP_NAMESPACE="${APP_NAMESPACE:-app-ns}"
APP_SA="${APP_SA:-payment-processor}"
OIDC_AUDIENCE="${OIDC_AUDIENCE:-vault}"
VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"

export VAULT_ADDR

echo "[1/5] Fetching OIDC Discovery Issuer URL from AWS EKS cluster: ${CLUSTER_NAME}..."
OIDC_ISSUER_URL=$(aws eks describe-cluster \
  --name "${CLUSTER_NAME}" \
  --region "${AWS_REGION}" \
  --query "cluster.identity.oidc.issuer" \
  --output text)

echo "      -> Discovered EKS OIDC Issuer: ${OIDC_ISSUER_URL}"

echo "[2/5] Enabling KV-v2 secrets engine and seeding sample secrets..."
vault secrets enable -path=secret kv-v2 2>/dev/null || echo "      -> KV-v2 already enabled at secret/"

vault kv put secret/payment-processor/config \
  DB_HOST="prod-payments-cluster.cluster-ro-abc123xyz.${AWS_REGION}.rds.amazonaws.com" \
  DB_USER="svc_payment_app" \
  DB_PASSWORD="vlt_dyn_9f8e7d6c5b4a3210_secretless" \
  STRIPE_API_KEY="sk_test_51SecretlessOIDCVaultDemoKey998877" \
  WEBHOOK_HMAC_KEY="whsec_oidc_verified_ephemeral_secret_2026"

echo "[3/5] Writing least-privilege Vault policy (${APP_SA}-policy)..."
vault policy write "${APP_SA}-policy" - <<EOF
path "secret/data/payment-processor/*" {
  capabilities = ["read"]
}
path "secret/metadata/payment-processor/*" {
  capabilities = ["list"]
}
EOF

echo "[4/5] Enabling Vault JWT/OIDC auth method and configuring EKS OIDC Discovery..."
vault auth enable jwt 2>/dev/null || echo "      -> JWT auth backend already enabled"

vault write auth/jwt/config \
  oidc_discovery_url="${OIDC_ISSUER_URL}" \
  bound_issuer="${OIDC_ISSUER_URL}"

echo "[5/5] Creating bound JWT role for system:serviceaccount:${APP_NAMESPACE}:${APP_SA}..."
vault write "auth/jwt/role/${APP_SA}" \
  role_type="jwt" \
  bound_audiences="${OIDC_AUDIENCE}" \
  user_claim="sub" \
  bound_subject="system:serviceaccount:${APP_NAMESPACE}:${APP_SA}" \
  token_policies="${APP_SA}-policy" \
  token_ttl="15m" \
  token_max_ttl="1h"

echo "=============================================================================="
echo "SUCCESS: Vault OIDC Workload Authentication is configured and ready!"
echo "=============================================================================="
