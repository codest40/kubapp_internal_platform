#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# REMOVE APP FROM GITOPS + SHARED INGRESS
#
# Responsibilities:
# - Remove service route from shared ingress
# - Remove gitops/envs/<env>/<service>/
# - Validate structure after deletion
# - Explicit validation before delete
# =========================================================

SERVICE="${1:?SERVICE is required}"
ENV="${2:?ENV is required}"

fail() {
  echo "❌ $1"
  exit 1
}

require() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing dependency: $1"
}

[[ -n "$SERVICE" ]] || fail "Usage: ./scripts/remove_app.sh <service> <env>"
[[ -n "$ENV" ]] || fail "Usage: ./scripts/remove_app.sh <service> <env>"

require yq

APP_DIR="gitops/envs/$ENV/apps/$SERVICE"

# Adjust this if your shared ingress file differs
INGRESS_FILE="gitops/ingress/$ENV/values.yaml"

[[ -d "$APP_DIR" ]] || fail "App directory not found: $APP_DIR"
[[ -f "$INGRESS_FILE" ]] || fail "Ingress file not found: $INGRESS_FILE"

echo ""
echo "======================================"
echo "REMOVE APPLICATION"
echo "======================================"
echo "Service : $SERVICE"
echo "Env     : $ENV"
echo "App Dir : $APP_DIR"
echo "Ingress : $INGRESS_FILE"
echo ""

####################################################
# STEP 1 — REMOVE FROM INGRESS
####################################################
echo "Checking ingress registration for $SERVICE..."

if yq e '.services[].name' "$INGRESS_FILE" | grep -qx "$SERVICE"; then
  echo "Removing ingress route for $SERVICE..."

  yq e '
    .services |= map(
      select(.name != "'"$SERVICE"'")
    )
  ' -i "$INGRESS_FILE"

  echo "✅ Ingress route removed"
  echo "log action+date to cloudwatch"
else
  echo "ℹ️ Service not found in ingress list — skipping removal"
fi

####################################################
# STEP 2 — REMOVE APP DIRECTORY
####################################################
echo ""
echo "Removing app directory..."

if [[ -d "$APP_DIR" ]]; then
  rm -rf "$APP_DIR"
  echo "✅ Removed: $APP_DIR"
  echo "log action+date to cloudwatch"

else
  echo "$APP_DIR Not a directory"
fi

####################################################
# STEP 3 — VALIDATE GITOPS STRUCTURE
####################################################
echo ""
echo "Running GitOps validation..."

if [[ -f "scripts/validate_gitops.sh" ]]; then
  bash scripts/validate_gitops.sh
  echo "✅ Validation passed"
else
  echo "ℹ️ validate_gitops.sh not found, skipping"
fi

####################################################
# FINAL SUMMARY
####################################################
echo ""
echo "======================================"
echo "✅ REMOVE SUMMARY"
echo "======================================"
echo "Removed:"
echo "- ingress route for $SERVICE"
echo "- app folder: $APP_DIR"
echo ""
echo "No auto commit performed"
echo "Review changes, then:"
echo ""
echo "git add gitops/"
echo "git commit -m \"remove ${SERVICE}-${ENV}\""
echo "git push"
echo ""
