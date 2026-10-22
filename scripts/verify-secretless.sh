#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Secretless Workload Verification & Security Audit Script
# ==============================================================================

NAMESPACE="${APP_NAMESPACE:-app-ns}"

echo "=============================================================================="
echo "1. Auditing Kubernetes Secrets in namespace '${NAMESPACE}'..."
echo "=============================================================================="
SECRET_COUNT=$(kubectl get secrets -n "${NAMESPACE}" --no-headers 2>/dev/null | wc -l | tr -d ' ')
echo "Found ${SECRET_COUNT} Kubernetes Secret object(s) in namespace '${NAMESPACE}'."
if [ "${SECRET_COUNT}" -eq 0 ]; then
  echo "[PASS] Zero static Kubernetes Secret objects exist in '${NAMESPACE}'!"
else
  kubectl get secrets -n "${NAMESPACE}"
fi

echo ""
echo "=============================================================================="
echo "2. Inspecting Projected OIDC JWT Token inside the SDK Workload Pod..."
echo "=============================================================================="
SDK_POD=$(kubectl get pods -n "${NAMESPACE}" -l pattern=direct-oidc-sdk -o jsonpath='{.items[0].metadata.name}')
echo "Target Pod: ${SDK_POD}"

kubectl exec -n "${NAMESPACE}" "${SDK_POD}" -- python3 -c '
import base64, json
with open("/var/run/secrets/tokens/vault-token") as f:
    jwt = f.read().strip()
header, payload, _ = jwt.split(".")
decode = lambda s: json.loads(base64.urlsafe_b64decode(s + "=" * (-len(s) % 4)).decode())
print("--- JWT Header ---")
print(json.dumps(decode(header), indent=2))
print("--- JWT Claims (Payload) ---")
print(json.dumps(decode(payload), indent=2))
'

echo ""
echo "=============================================================================="
echo "3. Checking Workload Logs for Successful OIDC -> Vault Authentication..."
echo "=============================================================================="
echo "--- Pattern B (Direct OIDC SDK In-Memory) Logs ---"
kubectl logs -n "${NAMESPACE}" "${SDK_POD}" --tail=10

echo ""
AGENT_POD=$(kubectl get pods -n "${NAMESPACE}" -l pattern=vault-agent-sidecar -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -n "${AGENT_POD}" ]; then
  echo "--- Pattern A (Vault Agent Sidecar tmpfs) Logs ---"
  kubectl logs -n "${NAMESPACE}" "${AGENT_POD}" -c app --tail=10
fi
