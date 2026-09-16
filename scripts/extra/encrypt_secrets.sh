#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$ROOT" ]]; then
    echo "[ERROR] Unable to determine project root."
    exit 1
fi
source "$ROOT/reuse.sh"

STACKS=("infra" "k8s" "manifests")
ENV="${1:-dev}"

echo
echo "=================================================="
echo "[INFO] SECRETS ENCRYPTION STARTED"
echo "[INFO] ENVIRONMENT: $ENV"
echo "[INFO] ROOT: $ROOT"
echo "=================================================="
echo

# =========================
# LOAD SETUP FUNCTIONS
# =========================
echo "--------------------------------------------------"
echo "[INFO] LOADING SOPS SETUP"
echo "--------------------------------------------------"

SETUP="./setup_sops.sh"
SETUP1="$ROOT/scripts/extra/setup_sops.sh"

if [[ -f "$SETUP" ]]; then
  echo "[INFO] Sourcing $SETUP"
  source "$SETUP"
elif [[ -f "$SETUP1" ]]; then
  echo "[INFO] Sourcing $SETUP1"
  source "$SETUP1"
else
  echo "[ERROR] ❌ setup_sops.sh not found"
  exit 1
fi

echo

# =========================
# PREREQUISITES
# =========================
echo "--------------------------------------------------"
echo "[INFO] CHECKING PREREQUISITES"
echo "--------------------------------------------------"

install_sops
install_age
ensure_age_key

AGE_PUBLIC_KEY=$(get_age_public_key)

if [[ -z "$AGE_PUBLIC_KEY" ]]; then
  echo "[ERROR] ❌ Could not extract AGE public key"
  exit 1
fi

echo "[INFO] Using AGE key: $AGE_PUBLIC_KEY"
echo

get_envs() {
  case "$ENV" in
    dev) echo "dev" ;;
    prod) echo "prod" ;;
    all) echo "dev prod" ;;
    *) echo "[ERROR] ❌ Invalid env: $ENV"; exit 1 ;;
  esac
}

encrypt_tfvars() {
  local file="$1"
  local out="${file}.enc"

  echo "[INFO] Encrypting: $file -> $out"

  sops --encrypt \
    --age "$AGE_PUBLIC_KEY" \
    "$file" > "$out"
}

echo "--------------------------------------------------"
echo "[INFO] TERRAFORM SECRETS ENCRYPTION"
echo "--------------------------------------------------"

for env in $(get_envs); do
  echo "[INFO] ENV: $env"

  for stack in "${STACKS[@]}"; do
    DIR="$ROOT/iac/$stack/envs/$env"

    if [[ -d "$DIR" ]]; then
      echo "[INFO] Directory found: $DIR"
    else
      echo "[WARN] ⚠️ Directory not found: $DIR"
      continue
    fi

    echo "[INFO] Processing stack: $stack"

    for tfvars in "$DIR"/*.tfvars; do
      [[ -f "$tfvars" ]] || continue
      encrypt_tfvars "$tfvars"
    done
  done

  echo
done

# SHARED HELPERS
is_encrypted() {
  grep -q '^sops:' "$1"
}

backup_file() {
  local file="$1"
  local backup="${file}.bak"

  cp -f "$file" "$backup"
  echo "[INFO] Backup created: $backup"
  echo "$backup"
}

decrypt_file() {
  local file="$1"
  echo "[INFO] Decrypting: $file"
  sops -d -i "$file"
}

process_secret_file() {
  local file="$1"
  local backup="${file}.bak"

  echo "[INFO] Processing: $file"

  # CASE 1: NOT ENCRYPTED
  if ! is_encrypted "$file"; then
    echo "[INFO] Plain file detected"
    backup_file "$file"
    sops -e -i "$file"
    echo "[INFO] Encrypted: $file"
    return
  fi

  # CASE 2: ENCRYPTED BUT NO BACKUP
  if is_encrypted "$file" && [[ ! -f "$backup" ]]; then
    echo "[WARN] Encrypted but missing backup"
    decrypt_file "$file"
    backup_file "$file"
    sops -e -i "$file"
    echo "[INFO] Re-encrypted after recovery: $file"
    return
  fi

  # CASE 3: SAFE STATE
  echo "[INFO] Already safe (encrypted + backup exists)"
}

echo "--------------------------------------------------"
echo "[INFO] GITOPS SECRETS ENCRYPTION"
echo "--------------------------------------------------"

GITOPS_DIR="$(cd $ROOT/gitops/secrets && pwd)"

echo "[INFO] Target directory: $GITOPS_DIR"

[[ -d "$GITOPS_DIR" ]] || {
  echo "[ERROR] ❌ Directory not found: $GITOPS_DIR"
  exit 1
}

shopt -s nullglob

for file in "$GITOPS_DIR"/**/*.yaml "$GITOPS_DIR"/**/*.yml; do
  #echo "=====================Found a File: $file ============"
  [[ -f "$file" ]] || continue
  process_secret_file "$file"
done

echo "--------------------------------------------------"
echo "[INFO] DOCKER SECRETS ENCRYPTION"
echo "--------------------------------------------------"

DOCKER_DIR="$(cd $ROOT/docker && pwd)"

echo "[INFO] Target directory: $DOCKER_DIR"

[[ -d "$DOCKER_DIR" ]] || {
  echo "[ERROR] ❌ Directory not found: $DOCKER_DIR"
  exit 1
}

while IFS= read -r -d '' file; do
  [[ -f "$file" ]] || continue
  process_secret_file "$file"
done < <(
  find "$DOCKER_DIR" -type f \( \
    -name "secrets.yml" -o \
    -name "secrets.yaml" -o \
    -name "secret.yml" -o \
    -name "secret.yaml" \
  \) -print0
)

echo
echo "=================================================="
echo "[INFO](encrypt_secrets.sh) ✅ ENCRYPTION COMPLETE"
echo "=================================================="
