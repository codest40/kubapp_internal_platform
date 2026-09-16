#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# CREATE / UPDATE KUBERNETES SECRET FROM SOPS FILE
# Usage:
#   create_secret.sh <artifact-json>
# =========================================================

ARTIFACT_FILE="${1:-}"

fail() {
  echo "❌ $1"
  exit 1
}

line() {
  printf '%*s\n' "${1:-60}" '' | tr ' ' '#'
  echo ">>> SCRIPT: $0 <<<"
}

require() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing dependency: $1"
}

line
[[ -n "$ARTIFACT_FILE" ]] || fail "Usage: create_secret.sh <artifact-json>"
[[ -f "$ARTIFACT_FILE" ]] || fail "Artifact file not found: $ARTIFACT_FILE"
case "$ARTIFACT_FILE" in
  gitops/*)
    echo "✅ Artifact is within GitOps scope: $ARTIFACT_FILE"
    ;;
  *)
    fail "❌ Security violation: artifact must be inside gitops/* (got: $ARTIFACT_FILE)"
    ;;
esac

require jq
require yq
require sops
require kubectl

# =========================================================
# LOAD ARTIFACT METADATA
# =========================================================
SERVICE=$(jq -r '.service' "$ARTIFACT_FILE")
CONTEXT=$(jq -r '.context' "$ARTIFACT_FILE")
NAMESPACE=$(jq -r '.namespace' "$ARTIFACT_FILE")
NO_SECRETS=$(jq -r '.NO_SECRETS' "$ARTIFACT_FILE")

[[ -n "$SERVICE" && "$SERVICE" != "null" ]] || fail "Invalid service in artifact"
[[ -n "$NAMESPACE" && "$NAMESPACE" != "null" ]] || fail "Invalid namespace in artifact"

echo "======================================"
echo " Secret Deployment"
echo " Service   : $SERVICE"
echo " Namespace : $NAMESPACE"
echo "======================================"

# =========================================================
# EXIT IF NO SECRETS
# =========================================================
if [[ -n "$NO_SECRETS" && "$NO_SECRETS" == "true" ]]; then
  echo "No secrets defined for $SERVICE"
  exit 0
elif [[ -z "$NO_SECRETS" ]]; then
  echo "❌ Secrets defined BUT Value for $SERVICE is Empty"
  exit 0
fi

# =========================================================
# LOCATE ENCRYPTED SECRET FILE
# =========================================================
SECRET_FILE=""

for file in \
  "$CONTEXT/secrets.yaml" \
  "$CONTEXT/secrets.yml"  \
  "$CONTEXT/secret.yaml" \
  "$CONTEXT/secret.yml"
do
  if [[ -f "$file" && -s "$file" ]]; then
    SECRET_FILE="$file"
    break
  fi
done

[[ -n "$SECRET_FILE" ]] || fail "NO_SECRETS=false but encrypted secret file not found"

echo "Using encrypted file: $SECRET_FILE"

# =========================================================
# DECRYPT
# =========================================================
TMP_DEC=$(mktemp)
TMP_SECRET=$(mktemp)

cleanup() {
  rm -f "$TMP_DEC" "$TMP_SECRET"
}
trap cleanup EXIT

sops -d "$SECRET_FILE" > "$TMP_DEC"

# =========================================================
# VALIDATE STRUCTURE
# Expected:
# secrets:
#   KEY: VALUE
# =========================================================
COUNT=$(yq e '.secrets // {} | length' "$TMP_DEC")

if [[ "$COUNT" -eq 0 ]]; then
  echo "No secret entries found"
  exit 0
fi

echo "Found $COUNT secret entries"

# =========================================================
# BUILD SECRET MANIFEST
# =========================================================
SECRET_NAME="${SERVICE}-secrets"

if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
  echo "Namespace '$NAMESPACE' does not exist. Creating..."
  kubectl create namespace "$NAMESPACE"
fi

kubectl create secret generic "$SECRET_NAME" \
  -n "$NAMESPACE" \
  --from-env-file=<(yq e '.secrets | to_entries | .[] | "\(.key)=\(.value)"' "$TMP_DEC") \
  --dry-run=client -o yaml > "$TMP_SECRET"

# =========================================================
# APPLY SECRET
# =========================================================
kubectl apply -f "$TMP_SECRET"

echo "✅ Secret applied: $SECRET_NAME"

