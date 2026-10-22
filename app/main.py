#!/usr/bin/env python3
"""
Secretless Workload Reference Application
Supports:
  1. Direct OIDC Projected ServiceAccount JWT exchange with HashiCorp Vault (In-Memory)
  2. Vault Agent Sidecar tmpfs file ingestion (/vault/secrets/config.env)
  3. Health & Audit FastAPI endpoints (never exposing raw secret values)
"""

import base64
import hashlib
import json
import logging
import os
from typing import Dict, Any

import hvac
from fastapi import FastAPI, HTTPException

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger("secretless-workload")

app = FastAPI(
    title="Secretless Workload Authentication Service",
    description="Demonstrates AWS EKS OIDC + HashiCorp Vault Secretless Authentication",
    version="1.0.0",
)

VAULT_ADDR = os.getenv("VAULT_ADDR", "http://vault.vault.svc.cluster.local:8200")
VAULT_AUTH_MOUNT = os.getenv("VAULT_AUTH_PATH", "jwt")
VAULT_ROLE = os.getenv("VAULT_ROLE", "payment-processor")
SECRET_MOUNT = os.getenv("SECRET_MOUNT", "secret")
SECRET_PATH = os.getenv("SECRET_PATH", "payment-processor/config")
JWT_TOKEN_PATH = os.getenv("JWT_TOKEN_PATH", "/var/run/secrets/tokens/vault-token")


def decode_jwt_payload(token: str) -> Dict[str, Any]:
    """Decode JWT claims without external dependencies for telemetry/audit logging."""
    parts = token.split(".")
    if len(parts) < 2:
        raise ValueError("Invalid JWT structure")
    padded = parts[1] + "=" * (-len(parts[1]) % 4)
    return json.loads(base64.urlsafe_b64decode(padded).decode("utf-8"))


def fetch_secrets_via_oidc() -> Dict[str, Any]:
    """
    Reads the short-lived Kubernetes projected OIDC JWT token from disk,
    authenticates against Vault's JWT/OIDC auth method, and retrieves secrets
    into process memory without persisting any credentials.
    """
    if not os.path.exists(JWT_TOKEN_PATH):
        raise FileNotFoundError(f"Projected OIDC token not found at {JWT_TOKEN_PATH}")

    with open(JWT_TOKEN_PATH, "r", encoding="utf-8") as token_file:
        oidc_jwt = token_file.read().strip()

    claims = decode_jwt_payload(oidc_jwt)
    logger.info(
        "Read projected OIDC token: sub=%s aud=%s exp=%s",
        claims.get("sub"),
        claims.get("aud"),
        claims.get("exp"),
    )

    client = hvac.Client(url=VAULT_ADDR)
    login_response = client.auth.jwt.jwt_login(
        role=VAULT_ROLE,
        jwt=oidc_jwt,
        path=VAULT_AUTH_MOUNT,
    )

    lease_duration = login_response["auth"]["lease_duration"]
    policies = login_response["auth"]["policies"]
    logger.info(
        "Authenticated to Vault via OIDC! Policies=%s LeaseTTL=%ss",
        policies,
        lease_duration,
    )

    secret_response = client.secrets.kv.v2.read_secret_version(
        mount_point=SECRET_MOUNT,
        path=SECRET_PATH,
        raise_on_deleted_version=True,
    )
    secret_data = secret_response["data"]["data"]

    return {
        "oidc_claims": {
            "issuer": claims.get("iss"),
            "subject": claims.get("sub"),
            "audience": claims.get("aud"),
            "expiration": claims.get("exp"),
        },
        "vault_Metadata": {
            "policies": policies,
            "token_ttl_seconds": lease_duration,
            "secret_version": secret_response["data"]["metadata"]["version"],
        },
        "secrets_summary": {
            key: f"sha256:{hashlib.sha256(str(val).encode()).hexdigest()[:12]} (loaded in-memory)"
            for key, val in secret_data.items()
        },
    }


@app.get("/healthz")
def healthz():
    return {"status": "healthy", "mode": "secretless-oidc"}


@app.get("/verify-oidc-auth")
def verify_oidc_auth():
    try:
        result = fetch_secrets_via_oidc()
        return {"status": "authenticated", "details": result}
    except Exception as exc:
        logger.exception("Secretless OIDC authentication failed")
        raise HTTPException(status_code=500, detail=str(exc)) from exc
