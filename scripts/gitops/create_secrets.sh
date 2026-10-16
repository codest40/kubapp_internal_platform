#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# CREATE / UPDATE KUBERNETES SECRET FROM SOPS FILE
# Usage:
#   create_secrets.sh <artifact-json>
# =========================================================

ARTIFACT_FILE="${1:-}"
DB_SECRET_DIR="gitops/secret_mgt/db"

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

[[ -n "$ARTIFACT_FILE" ]] || fail "Usage: create_secrets.sh <artifact-json>"
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
SECRET_FILE=$(jq -r '.secret_file' "$ARTIFACT_FILE")
NAMESPACE=$(jq -r '.namespace' "$ARTIFACT_FILE")
NO_SECRETS=$(jq -r '.NO_SECRETS' "$ARTIFACT_FILE")
DB_ACCESS=$(jq -r '.dbAccess // false' "$ARTIFACT_FILE")

[[ -n "$SERVICE" && "$SERVICE" != "null" ]] \
  || fail "Invalid service in artifact"

[[ -n "$NAMESPACE" && "$NAMESPACE" != "null" ]] \
  || fail "Invalid namespace in artifact"

echo "======================================"
echo " Secret Deployment"
echo " Service   : $SERVICE"
echo " Namespace : $NAMESPACE"
echo " DB Access : $DB_ACCESS"
echo "======================================"

# =========================================================
# RETURN IF NO SECRETS
# =========================================================
if [[ "$NO_SECRETS" == "true" && "$DB_ACCESS" != "true" ]]; then
  echo "No secrets defined for $SERVICE"
  exit 0
fi

# =========================================================
# APPLICATION SECRET
# =========================================================
if [[ "$NO_SECRETS" == "false" ]]; then

   [[ -f "$SECRET_FILE" ]] \
    || fail "NO_SECRETS=false but encrypted secret file not found"

  echo "Using application secret: $SECRET_FILE"

  TMP_DEC=$(mktemp)
  TMP_SECRET=$(mktemp)

  cleanup() {
    rm -f "$TMP_DEC" "$TMP_SECRET"
  }

  trap cleanup EXIT

  sops -d "$SECRET_FILE" > "$TMP_DEC"

  # =======================================================
  # VALIDATE STRUCTURE
  # Expected:
  # secrets:
  #   KEY: VALUE
  # =======================================================
  COUNT=$(yq e '.secrets // {} | length' "$TMP_DEC")

  if [[ "$COUNT" -eq 0 ]]; then
    echo "No application secret entries found"
  else
    echo "Found $COUNT application secret entries"

    SECRET_NAME="${SERVICE}-secrets"

    if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
      echo "Namespace '$NAMESPACE' does not exist. Creating..."
      kubectl create namespace "$NAMESPACE"
    fi

    kubectl create secret generic "$SECRET_NAME" \
      -n "$NAMESPACE" \
      --from-env-file=<(yq e '.secrets | to_entries | .[] | "\(.key)=\(.value)"' "$TMP_DEC") \
      --dry-run=client -o yaml > "$TMP_SECRET"

    kubectl apply -f "$TMP_SECRET"

    echo "✅ Application secret applied: $SECRET_NAME"
  fi

  rm -f "$TMP_DEC" "$TMP_SECRET"
  trap - EXIT
fi

# =========================================================
# DATABASE SECRET
# =========================================================
if [[ "$DB_ACCESS" == "true" ]]; then

  DB_SECRET_FILE="$DB_SECRET_DIR/kubapp-db-secrets.yml"
  [[ -f "$DB_SECRET_FILE" ]] \
  || fail "DB access enabled but encrypted DB secret file not found: $DB_SECRET_FILE"

  echo "Using platform DB secret: $DB_SECRET_FILE"

  TMP_DB_DEC=$(mktemp)
  TMP_DB_SECRET=$(mktemp)

  cleanup_db() {
    rm -f "$TMP_DB_DEC" "$TMP_DB_SECRET"
  }

  trap cleanup_db EXIT

  sops -d "$DB_SECRET_FILE" > "$TMP_DB_DEC"
  DB_STATUS=$(yq e -r '.secrets.DB_STATUS // "inactive"' "$TMP_DB_DEC")

  if [[ "$DB_STATUS" != "active" ]]; then
    echo "⚠️ Database access requested but database is inactive"
    exit 10
  fi

  DB_COUNT=$(yq e '.secrets // {} | length' "$TMP_DB_DEC")

  if [[ "$DB_COUNT" -eq 0 ]]; then
    fail "DB secret file contains no secret entries"
  fi

  echo "Found $DB_COUNT database secret entries"

  DB_SECRET_NAME="${SERVICE}-db-secrets"

  if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    echo "Namespace '$NAMESPACE' does not exist. Creating..."
    kubectl create namespace "$NAMESPACE"
  fi

  kubectl create secret generic "$DB_SECRET_NAME" \
    -n "$NAMESPACE" \
    --from-env-file=<(yq e '.secrets | to_entries | .[] | "\(.key)=\(.value)"' "$TMP_DB_DEC") \
    --dry-run=client -o yaml > "$TMP_DB_SECRET"

  kubectl apply -f "$TMP_DB_SECRET"

  echo "✅ Database secret applied: $DB_SECRET_NAME"

  rm -f "$TMP_DB_DEC" "$TMP_DB_SECRET"
  trap - EXIT
fi

