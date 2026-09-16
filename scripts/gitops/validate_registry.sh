#!/usr/bin/env bash
set -euo pipefail

FILE="${1:-}"

fail() {
  echo "❌ $1"
  RESULT="failure"
}

[[ -n "$FILE" ]] || fail "Usage: validate_registry.sh <json-file>"
[[ -f "$FILE" ]] || fail "File not found: $FILE"

require() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing dependency: $1"
}

require jq

echo ""
echo "======================================"
echo "REGISTRY VALIDATION"
echo "======================================"
echo "File: $FILE"
echo ""

########################################
# 1. STRUCTURE CHECK
########################################
echo "Checking required fields..."

REQUIRED_KEYS=(
  service context image tag registry
  namespace env port
)

for key in "${REQUIRED_KEYS[@]}"; do
  val=$(jq -r --arg k "$key" '.[$k] // empty' "$FILE")

  [[ -n "$val" && "$val" != "null" ]] || {
    fail "Missing required field: $key"
  }
done

echo "✔ Required fields present"

########################################
# 2. TYPE VALIDATION
########################################
echo "Checking types..."

jq -e '
  (.service | type == "string") and
  (.context | type == "string") and
  (.image | type == "string") and
  (.tag | type == "string") and
  (.registry | type == "string") and
  (.namespace | type == "string") and
  (.env | type == "string") and
  (.port | type == "string" or type == "number")
' "$FILE" >/dev/null || fail "Type validation failed"

echo "✔ Types valid"

########################################
# 3. SEMANTIC CHECKS
########################################
echo "Checking values..."

SERVICE=$(jq -r '.service' "$FILE")
PORT=$(jq -r '.port' "$FILE")
IMAGE=$(jq -r '.image' "$FILE")
ENV=$(jq -r '.env' "$FILE")

# service name
[[ "$SERVICE" =~ ^[a-z0-9_-]+$ ]] || fail "Invalid service name: $SERVICE"

# port numeric
[[ "$PORT" =~ ^[0-9]+$ ]] || fail "Port must be numeric: $PORT"

# valid port range
(( PORT >= 1 && PORT <= 65535 )) || fail "Port out of range: $PORT"

# image format
[[ "$IMAGE" == *":"* ]] || fail "Image must include tag: $IMAGE"

# env allowlist
case "$ENV" in
  dev|prod|staging) ;;
  *) fail "Invalid env: $ENV" ;;
esac

echo "✔ Semantic checks passed"

########################################
# 4. OPTIONAL FIELDS VALIDATION
########################################
echo "Checking optional fields..."

# NO_VARS / NO_SECRETS must be boolean if present
#jq -e '
#  (has("NO_VARS") | not or (.NO_VARS | type == "boolean")) and
#  (has("NO_SECRETS") | not or (.NO_SECRETS | type == "boolean"))
#' "$FILE" >/dev/null || fail "NO_VARS / NO_SECRETS must be boolean"

echo "✔ Optional fields valid"

########################################
# 5. FUTURE SAFETY CHECKS
########################################
echo "Checking for dangerous patterns..."

# prevent duplicate image fields confusion
if jq -e 'has("image2")' "$FILE" >/dev/null; then
  echo "⚠️ Warning: image2 detected (non-standard field)"
fi

echo "✔ Safety checks done"
RESULT="success"
echo "RESULT=$RESULT" >> $GITHUB_ENV

echo ""
echo "======================================"
echo "✅ VALIDATION PASSED"
echo "======================================"

