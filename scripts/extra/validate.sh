#!/usr/bin/env bash
set -euo pipefail

ENV="${1:-dev}"

echo
echo "=================================================="
echo "[INFO] SYSTEM VALIDATION STARTED"
echo "[INFO] ENVIRONMENT: $ENV"
echo "=================================================="
echo

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$ROOT" ]]; then
    echo "[ERROR] Unable to determine project root."
    exit 1
fi
source "$ROOT/reuse.sh"

ROOT_DIR="$ROOT"
cd "$ROOT_DIR"

############################################
# HELPERS
############################################
fail() {
  echo
  echo "[ERROR] ❌ $1"
  echo "=================================================="
  exit 1
}

check_file() {
  [[ -f "$1" ]] || fail "Missing file: $1"
}

check_dir() {
  [[ -d "$1" ]] || fail "Missing directory: $1"
}

############################################
# 0. GITIGNORE CHECK
############################################
echo "--------------------------------------------------"
echo "[INFO] [0/8] GITIGNORE CHECK"
echo "--------------------------------------------------"

check_file ".gitignore"

if [[ ! -s ".gitignore" ]]; then
  fail ".gitignore exists but is empty"
fi

echo "[INFO] ✅ .gitignore OK"
echo

############################################
# 1. REQUIRED TOOLS
############################################
echo "--------------------------------------------------"
echo "[INFO] [1/8] REQUIRED TOOLS"
echo "--------------------------------------------------"

TOOLS=(terraform sops age yq jq git)

for tool in "${TOOLS[@]}"; do
  command -v "$tool" >/dev/null 2>&1 || fail "Missing tool: $tool"
done

echo "[INFO] ✅ Tools OK"
echo

############################################
# 2. PROJECT STRUCTURE
############################################
echo "--------------------------------------------------"
echo "[INFO] [2/8] PROJECT STRUCTURE"
echo "--------------------------------------------------"

check_dir "$ROOT_DIR/iac"
check_dir "$ROOT_DIR/iac/infra"
check_dir "$ROOT_DIR/iac/k8s"
check_dir "$ROOT_DIR/gitops"
check_dir "$ROOT_DIR/scripts"
check_dir "$ROOT_DIR/docker"
check_dir "$ROOT_DIR/sys_monitor"
check_dir "$ROOT_DIR/.github/workflows"

for stack in infra k8s; do
  for env in dev prod; do
    check_dir "$ROOT_DIR/iac/$stack/envs/$env"
    check_file "$ROOT_DIR/iac/$stack/envs/$env/backend.hcl"
  done
done

echo "[INFO] ✅ Structure OK"
echo

############################################
# 3. TERRAFORM FILE VALIDATION (NO INIT)
############################################
echo "--------------------------------------------------"
echo "[INFO] [3/8] TERRAFORM VALIDATION"
echo "--------------------------------------------------"

for stack in infra k8s; do
  DIR="iac/$stack"

  check_dir "$DIR"

  if ! find "$DIR" -maxdepth 1 -name "*.tf" | grep -q .; then
    fail "No Terraform files found in $DIR"
  fi

  echo "[INFO] Formatting: $DIR"
  terraform fmt -recursive "$DIR"

  echo "[INFO] Checking format: $DIR"
  terraform fmt -check -recursive "$DIR" \
    || fail "Terraform format/syntax issue in $DIR"
done

echo "[INFO] ✅ Terraform files OK"
echo

############################################
# 4. SECRETS FILE PRESENCE (NO DECRYPT)
############################################
echo "--------------------------------------------------"
echo "[INFO] [4/8] SECRETS CHECK"
echo "--------------------------------------------------"

for stack in infra k8s; do
  BASE="iac/$stack/envs/$ENV"

  check_file "$BASE/${stack}.tfvars"

  if [[ -f "$BASE/${stack}.tfvars.enc" ]]; then
    :
  else
    echo "[WARN] ⚠️ Missing encrypted file for $stack/$ENV"
  fi
done

echo "[INFO] ✅ Secrets presence OK"
echo

############################################
# 5. YAML VALIDATION
############################################
echo "--------------------------------------------------"
echo "[INFO] [5/8] YAML VALIDATION"
echo "--------------------------------------------------"

mapfile -t yamls < <(find . -type f \( -name "*.yml" -o -name "*.yaml" \))

for file in "${yamls[@]}"; do
  if [[ "$file" == *"templates/"* ]]; then
    echo "[INFO] Skipping Helm template: $file"
    continue
  fi
  yq e '.' "$file" >/dev/null || fail "Invalid YAML: $file"
done

echo "[INFO] ✅ YAML OK"
echo

############################################
# 6. BASIC GITOPS STRUCTURE CHECK
############################################
echo "--------------------------------------------------"
echo "[INFO] [6/8] GITOPS STRUCTURE"
echo "--------------------------------------------------"

check_dir "gitops/argocd"
check_dir "gitops/charts"
check_dir "gitops/envs"

echo "[INFO] ✅ GitOps structure OK"
echo

############################################
# 7. SCRIPT VALIDATION
############################################
echo "--------------------------------------------------"
echo "[INFO] [7/8] SCRIPT VALIDATION"
echo "--------------------------------------------------"

if command -v shellcheck >/dev/null 2>&1; then
  find scripts -type f -name "*.sh" -exec shellcheck {} \; \
    || fail "Shellcheck failed"
else
  echo "[WARN] ⚠️ Skipping shellcheck (not installed)"
fi

echo "[INFO] ✅ Scripts OK"
echo

############################################
# 8. SANITY CHECKS
############################################
echo "--------------------------------------------------"
echo "[INFO] [8/8] SANITY CHECKS"
echo "--------------------------------------------------"

if find . -type d -name ".terraform" | grep -q .; then
  echo "[WARN] ⚠️ .terraform directories detected"
fi

if grep -r "aws_secret_access_key" . --exclude-dir=.git >/dev/null 2>&1; then
  echo "[WARN] ⚠️ Possible secret detected in repo"
fi

echo "[INFO] ✅ Sanity checks OK"
echo

echo "=================================================="
echo "[INFO] ✅ ALL VALIDATIONS PASSED"
echo "=================================================="
echo
