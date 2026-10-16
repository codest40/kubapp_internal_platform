#!/usr/bin/env bash
set -euo pipefail

ENV="${1:-dev}"
PUSH="${PUSH:-false}"
APPS="${APPS:-false}"
ACTION="${ACTION:-rebase}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"

if [[ -z "$ROOT" ]]; then
    echo "[ERROR] Unable to determine project root."
    exit 1
fi

source "$ROOT/reuse.sh"

if [[ "${ACTION,,}" != "rebase" &&  "${ACTION,,}" != "diagnose" ]]; then
  source "$ROOT/scripts/extra/activate_usage.sh"
  show_activate_usage
  exit 1
fi

source "$ROOT/scripts/extra/git_functions1.sh"
source "$ROOT/scripts/extra/git_functions2.sh"
source "$ROOT/scripts/extra/git_diagnosis.sh"
check_nested_git_repos || exit 1

echo "=============================="
echo "ACTIVATION PIPELINE"
echo "ENV: $ENV"
echo "ROOT: $ROOT"
echo "=============================="

if [[  "${ACTION,,}" == "diagnose" ]]; then
    echo "[INFO] DIAGNOSING GIT STATE"
    echo "--------------------------------------------------"
    diagnose_git_repository
    exit 1
fi

############################################
# 1. GIT PREPARATION
############################################
echo "--------------------------------------------------"
echo "[INFO] PREPARING GIT STATE"
echo "--------------------------------------------------"

apply_git rebase prepare

############################################
# 2. VALIDATION
############################################
echo "[ACTIVATE] RUNNING VALIDATE SCRIPT..."
./scripts/extra/validate.sh "$ENV"

############################################
# 3. PRE-FLIGHT EXECUTION SCRIPTS
############################################
echo "[ACTIVATE] RUNNING ENCRYPT SECRETS SCRIPT..."
./scripts/extra/encrypt_secrets.sh "$ENV"

echo "[ACTIVATE] RUNNING VALIDATE GITOPS SCRIPT..."
./scripts/gitops/validate_gitops.sh

if [[ "${APPS,,}" == "true" || "${APPS,,}" == "yes" ]]; then
echo "[ACTIVATE] RUNNING VALIDATE APPLICATIONS SCRIPT..."
./scripts/extra/validate_kubapp_apps.sh
fi

############################################
# 4. GIT FINALIZATION
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

if [[ "${PUSH,,}" != "true" && "${PUSH,,}" != "yes" ]]; then
    read -rp "Push to GitHub? (yes/no): " CONFIRM

    if [[ "${CONFIRM,,}" != "yes" ]]; then
        echo "[WARN] ⚠️ Push skipped by user"
        End
    fi
fi

COMMIT_MSG="[CHORE (Activate)]: run activation pipeline for $ENV - $(date '+%Y-%m-%d %H:%M:%S')"
apply_git rebase finalize "$COMMIT_MSG"
End
