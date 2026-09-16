#!/usr/bin/env bash
set -euo pipefail

SERVICE="${1:?SERVICE NAME Required}"
ENV="${2:?ENV Must Be Supplied}"

fail() { echo "❌ $1"; exit 1; }

require() { command -v "$1" >/dev/null 2>&1 || fail "Missing $1"; }

require jq
require yq

FILE="gitops/envs/$ENV/$SERVICE/values.yaml"

[[ -f "$FILE" ]] || fail "values.yaml not found: $FILE"

echo ""
echo "SELF-HEAL DRIFT ANALYSIS"
echo "Service: $SERVICE"
echo "Env:     $ENV"
echo "File:    $FILE"
echo "-----------------------------------"

####################################################
# 1. STRUCTURAL DRIFT
####################################################
SERVICE_NAME=$(yq e '.appName' "$FILE")
IMAGE=$(yq e '.image.repository' "$FILE")
TAG=$(yq e '.image.tag' "$FILE")
PORT=$(yq e '.service.targetPort' "$FILE")

EXPECTED_FP=$(yq e '.meta.staticFingerprint' "$FILE")

COMPUTED_FP=$(echo -n "$SERVICE_NAME|$TAG|$ENV|$PORT" | sha256sum | awk '{print $1}')

if [[ "$EXPECTED_FP" != "$COMPUTED_FP" ]]; then
  echo ""
  echo "STRUCTURAL DRIFT DETECTED"
  echo "-----------------------------------"
  echo "Expected fingerprint : $EXPECTED_FP"
  echo "Current computed     : $COMPUTED_FP"
  echo ""

  echo "🛠Suggested fix:"
  echo "  ./scripts/create_values.sh <latest-artifact>"
  echo ""

  STRUCT_DRIFT=true
else
  echo "✔ Structural state OK"
  STRUCT_DRIFT=false
fi

####################################################
# 2. RUNTIME DRIFT
####################################################
TMP_ENV=$(mktemp)

yq e '.env | to_entries | sort_by(.key)' "$FILE" > "$TMP_ENV"
RUNTIME_HASH=$(sha256sum "$TMP_ENV" | awk '{print $1}')

STORED_RUNTIME=$(yq e '.meta.runtimeHash // ""' "$FILE")

if [[ -n "$STORED_RUNTIME" && "$STORED_RUNTIME" != "$RUNTIME_HASH" ]]; then
  echo ""
  echo "⚠️ RUNTIME DRIFT DETECTED"
  echo "-----------------------------------"

  echo "Cause:"
  echo "- env or secret injection changed"
  echo ""

  echo "🛠 Suggested fix:"
  echo "  ./scripts/set_app_secret.sh <artifact-json>"
  echo ""

  RUNTIME_DRIFT=true
else
  echo "✔ Runtime state OK"
  RUNTIME_DRIFT=false
fi

####################################################
# 4. FINAL SUMMARY
####################################################
echo ""
echo "===================================="
echo " DRIFT SUMMARY"
echo "===================================="

if [[ "$STRUCT_DRIFT" == "true" || "$RUNTIME_DRIFT" == "true" ]]; then
  echo "❌ Drift detected for: $SERVICE"
  echo ""

  echo " Recommended pipeline order:"
  echo "   1. create_values.sh (structure)"
  echo "   2. set_app_secret.sh (runtime)"
  echo "   3. update.yml (image only)"
  echo ""

  exit 1
fi

echo "✅ System fully in sync"
exit 0
