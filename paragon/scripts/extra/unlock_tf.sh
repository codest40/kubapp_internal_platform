#!/usr/bin/env bash
set -euo pipefail

STACK="${1:-infra}"
ENV="${2:-dev}"
LOCK_ID="${3:-}"

ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$ROOT_DIR" ]]; then
    echo "[ERROR] Unable to determine project root."
    echo "Using manula method"
    ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi
BASE_DIR="$ROOT_DIR/iac/$STACK"
ENV_DIR="$BASE_DIR/envs/$ENV"

############################################
# HELPERS
############################################
fail() {
  echo "❌ $1"
  exit 1
}

check_dir() {
  [[ -d "$1" ]] || fail "Missing directory: $1"
}

############################################
# VALIDATION
############################################
echo "=============================="
echo "Terraform Lock Unlock Tool"
echo "Stack: $STACK"
echo "Env: $ENV"
echo "=============================="

check_dir "$BASE_DIR"
check_dir "$ENV_DIR"

if [[ -z "$LOCK_ID" ]]; then
  echo "❌ No LOCK_ID provided"
  echo "Usage: ./unlock_tf.sh <infra|k8s> <env> <lock_id>"
  exit 1
fi

LOCK_ID=$(echo "$LOCK_ID" | xargs)

cd "$BASE_DIR"
echo "Initializing backend..."
terraform init -backend-config="envs/${ENV}/backend.hcl" -input=false

############################################
# SHOW CONTEXT (SAFETY CHECK)
############################################
echo ""
echo "Checking lock details..."
echo ""
echo "⚠️ You are about to unlock:"
echo "   Stack: $STACK"
echo "   Env:   $ENV"
echo "   Lock:  $LOCK_ID"
echo ""

if [[ "${CI:-}" != "true" ]]; then
  read -rp "Type YES to confirm unlock: " CONFIRM

  if [[ "$CONFIRM" != "YES" ]]; then
    echo "Aborted."
    exit 0
  fi
fi

############################################
# UNLOCK
############################################
echo "Unlocking state..."
terraform force-unlock -force "$LOCK_ID"

echo ""
echo "✅ State lock released successfully"
