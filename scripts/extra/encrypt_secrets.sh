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

# =========================
# LOAD SOPS SETUP
# =========================
load_sops_setup() {
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
}

# =========================
# PREREQUISITES
# =========================
check_prerequisites() {
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
}

# =========================
# ENVIRONMENT
# =========================
get_envs() {
    case "$ENV" in
        dev)
            echo "dev"
            ;;
        prod)
            echo "prod"
            ;;
        all)
            echo "dev prod"
            ;;
        *)
            echo "[ERROR] ❌ Invalid env: $ENV"
            exit 1
            ;;
    esac
}

# =========================
# SHARED SECRET HELPERS
# =========================
is_encrypted() {
    grep -q '^sops:' "$1"
}

backup_file() {
    local file="$1"
    local backup="${file}.bak"

    cp -f "$file" "$backup"

    echo "[INFO] Backup created: $backup"
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

    # NOT ENCRYPTED
    if ! is_encrypted "$file"; then
        echo "[INFO] Plain file detected"

        backup_file "$file"
        sops -e -i "$file"

        echo "[INFO] Encrypted: $file"
        return
    fi

    # ENCRYPTED BUT NO BACKUP
    if [[ ! -f "$backup" ]]; then
        echo "[WARN] Encrypted but missing backup"

        decrypt_file "$file"
        backup_file "$file"
        sops -e -i "$file"

        echo "[INFO] Re-encrypted after recovery: $file"
        return
    fi

    # SAFE STATE
    echo "[INFO] Already safe (encrypted + backup exists)"
}

# =========================
# TERRAFORM SECRETS
# =========================
encrypt_tfvars() {
    echo "--------------------------------------------------"
    echo "[INFO] TERRAFORM SECRETS ENCRYPTION"
    echo "--------------------------------------------------"

    for env in $(get_envs); do
        echo "[INFO] ENV: $env"

        for stack in "${STACKS[@]}"; do
            local dir="$ROOT/iac/$stack/envs/$env"

            if [[ -d "$dir" ]]; then
                echo "[INFO] Directory found: $dir"
            else
                echo "[WARN] ⚠️ Directory not found: $dir"
                continue
            fi

            echo "[INFO] Processing stack: $stack"

            for tfvars in "$dir"/*.tfvars; do
                [[ -f "$tfvars" ]] || continue

                local out="${tfvars}.enc"

                echo "[INFO] Encrypting: $tfvars -> $out"

                sops --encrypt \
                    --age "$AGE_PUBLIC_KEY" \
                    "$tfvars" > "$out"
            done
        done

        echo
    done
}

# =========================
# GITOPS SECRETS
# =========================
encrypt_gitops_secrets() {
    echo "--------------------------------------------------"
    echo "[INFO] GITOPS SECRETS ENCRYPTION"
    echo "--------------------------------------------------"

    local dir="$ROOT/gitops/secrets"

    echo "[INFO] Target directory: $dir"

    [[ -d "$dir" ]] || {
        echo "[ERROR] ❌ Directory not found: $dir"
        exit 1
    }

    shopt -s nullglob

    for file in "$dir"/**/*.yaml "$dir"/**/*.yml; do
        [[ -f "$file" ]] || continue
        process_secret_file "$file"
    done
}

# =========================
# DOCKER SECRETS
# =========================
encrypt_docker_secrets() {
    echo "--------------------------------------------------"
    echo "[INFO] DOCKER SECRETS ENCRYPTION"
    echo "--------------------------------------------------"

    local dir="$ROOT/docker"

    echo "[INFO] Target directory: $dir"

    [[ -d "$dir" ]] || {
        echo "[ERROR] ❌ Directory not found: $dir"
        exit 1
    }

    while IFS= read -r -d '' file; do
        [[ -f "$file" ]] || continue
        process_secret_file "$file"
    done < <(
        find "$dir" -type f \( \
            -name "secrets.yml" -o \
            -name "secrets.yaml" -o \
            -name "secret.yml" -o \
            -name "secret.yaml" \
        \) -print0
    )
}

# =========================
# DATABASE SECRETS
# =========================
encrypt_database_secrets() {
    echo "--------------------------------------------------"
    echo "[INFO] DATABASE SECRETS ENCRYPTION"
    echo "--------------------------------------------------"

    local dir="$ROOT/iac/database/store/secrets"

    echo "[INFO] Target directory: $dir"

    if [[ ! -d "$dir" ]]; then
        echo "[WARN] ⚠️ Directory not found: $dir"
        return 0
    fi

    for file in "$dir"/*; do
        [[ -f "$file" ]] || continue
        process_secret_file "$file"
    done
}

echo
echo "=================================================="
echo "[INFO] SECRETS ENCRYPTION STARTED"
echo "[INFO] ENVIRONMENT: $ENV"
echo "[INFO] ROOT: $ROOT"
echo "=================================================="
echo

load_sops_setup
check_prerequisites

encrypt_tfvars
encrypt_gitops_secrets
encrypt_docker_secrets
encrypt_database_secrets

echo
echo "=================================================="
echo "[INFO](encrypt_secrets.sh) ✅ ENCRYPTION COMPLETE"
echo "=================================================="
