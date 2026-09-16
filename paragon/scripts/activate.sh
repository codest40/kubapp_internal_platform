#!/usr/bin/env bash
set -euo pipefail

ENV="${1:-dev}"
PUSH="${PUSH:-no}"
PUSH="${PUSH,,}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$ROOT" ]]; then
    echo "[ERROR] Unable to determine project root."
    exit 1
fi
source "$ROOT/reuse.sh"

echo "=============================="
echo "ACTIVATION PIPELINE"
echo "ENV: $ENV"
echo "ROOT: $ROOT"
echo "=============================="

############################################
# 1. VALIDATION (STRICT)
############################################
echo "[ACTIVATE] RUNNING VALIDATE SCRIPT..."
./scripts/extra/validate.sh "$ENV"

############################################
# 2. PRE-FLIGHT EXECUTION SCRIPTS
############################################
echo "[ACTIVATE] RUNNING ENCRYPT SECRETS SCRIPT..."

./scripts/extra/encrypt_secrets.sh "$ENV"

echo "[ACTIVATE] RUNNING VALIDATE GITOPS SCRIPT..."
./scripts/gitops/validate_gitops.sh

############################################
# 3. GIT PUSH
############################################
echo "--------------------------------------------------"
echo "[INFO] GIT OPERATIONS"
echo "--------------------------------------------------"

End() {
echo "====================================================="
echo "✅ ACTIVATION COMPLETE: $(date '+%Y-%m-%d_%H:%M:%S')"
echo "====================================================="
exit 0
}

if [[ "$PUSH" == "no" ]]; then
  read -rp "Push to GitHub? (yes/no): " CONFIRM
  if [[ "$CONFIRM" == "yes" ]]; then
    echo "[INFO] Staging changes..."
  else
    echo "[WARN] ⚠️ Push skipped by user"
    End
  fi
fi

git add .

COMMIT_MSG="[CHORE (Activate)]: run activation pipeline for $ENV - $(date '+%Y-%m-%d %H:%M:%S')"

echo "[INFO] Creating commit..."
git commit -m "$COMMIT_MSG" || echo "[WARN] ⚠️ No changes to commit"

echo "[INFO] Pushing to remote..."
if git push; then
  echo "[INFO] ✅ Push successful"
else
  echo "[WARN] ⚠️  Remote State Changed, Rebasing First..."
  git pull --rebase && git push
  echo "[INFO] ✅ Push successful"
fi

End || true
