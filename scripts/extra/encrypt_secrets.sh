#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"

if [[ -z "$ROOT" ]]; then
    echo "[ERROR] Unable to determine project root."
    exit 1
fi

source "$ROOT/reuse.sh"
source "$SCRIPT_DIR/secret_functions.sh"
source "$SCRIPT_DIR/tf_secret_functions.sh"

STACKS=("infra" "k8s" "manifests")
ENV="${1:-dev}"

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

    if ! command -v dotenv >/dev/null 2>&1; then
        echo "[ERROR] ❌ Required command 'dotenv' was not found."
        echo "[ERROR] Database secret reconciliation requires python-dotenv."
        echo "[ERROR] Check your Python environment and activate it if needed."
        echo "[ERROR] Example:"
        echo "        source <your-venv>/bin/activate"
        echo
        exit 1
    fi
    echo "[INFO] Using AGE key: $AGE_PUBLIC_KEY"
    echo
}

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

encrypt_gitops_secrets() {
    echo "--------------------------------------------------"
    echo "[INFO] GITOPS SECRETS ENCRYPTION"
    echo "--------------------------------------------------"

    local base_dir="$ROOT/gitops/secret_mgt"
    local secrets_dir="$base_dir/secrets"
    local db_dir="$base_dir/db"

    echo "[INFO] Base directory: $base_dir"

    [[ -d "$base_dir" ]] || {
        echo "[ERROR] ❌ Directory not found: $base_dir"
        exit 1
    }

    shopt -s nullglob globstar

    # =====================================================
    # gitops/secret_mgt/secrets/**
    # =====================================================

    if [[ -d "$secrets_dir" ]]; then
        echo "[INFO] Processing secrets directory: $secrets_dir"

        # Existing secrets
        for file in "$secrets_dir"/**/*.yaml "$secrets_dir"/**/*.yml; do
            [[ -f "$file" ]] || continue

            process_secret_file "$file"
        done

        # Recover deleted secrets from .bak
        for backup in "$secrets_dir"/**/*.yaml.bak "$secrets_dir"/**/*.yml.bak; do
            [[ -f "$backup" ]] || continue

            file="${backup%.bak}"

            if [[ ! -f "$file" ]]; then
                process_secret_file "$file"
            fi
        done
    else
        echo "[WARN] ⚠️ Directory not found: $secrets_dir"
    fi

    # =====================================================
    # gitops/secret_mgt/db/*.yml|*.yaml
    # =====================================================

    if [[ -d "$db_dir" ]]; then
        echo "[INFO] Processing database secrets: $db_dir"

        # Existing database secrets
        for file in "$db_dir"/*.yaml "$db_dir"/*.yml; do
            [[ -f "$file" ]] || continue

            process_secret_file "$file"
        done

        # Recover deleted database secrets from .bak
        for backup in "$db_dir"/*.yaml.bak "$db_dir"/*.yml.bak; do
            [[ -f "$backup" ]] || continue

            file="${backup%.bak}"

            if [[ ! -f "$file" ]]; then
                process_secret_file "$file"
            fi
        done
    else
        echo "[WARN] ⚠️ Directory not found: $db_dir"
    fi
}

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

process_database_env_secret() {
    local file="$1"

    echo "[INFO] Processing database secret: $file"

    process_secret_file "$file"
}

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

    shopt -s nullglob

    for file in "$dir"/*.env; do
        [[ -f "$file" ]] || continue

        process_database_env_secret "$file"
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

encrypt_tf_secrets "$ENV"
encrypt_gitops_secrets
encrypt_docker_secrets
encrypt_database_secrets

echo
echo "=================================================="
echo "[INFO](encrypt_secrets.sh) ✅ ENCRYPTION COMPLETE"
echo "=================================================="
