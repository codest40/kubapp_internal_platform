#!/usr/bin/env bash

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "❌ Unable to determine project root."
    return 1 2>/dev/null || exit 1
}

AWS_DIR="$ROOT/sys_monitor/cloud/aws"
MAIN_DIR="$AWS_DIR/main"
SECRET_DIR="$AWS_DIR/store/secrets"

BACKEND_SOURCE="$ROOT/sys_monitor/backend/.env"
DEPLOY_KEY_SOURCE="$HOME/.ssh/sys_monitor_deploy"

BACKEND_SECRET="$SECRET_DIR/backend.env.enc"
DEPLOY_KEY_SECRET="$SECRET_DIR/github-deploy-key.env.enc"


encrypt_backend_env() {
    if [[ ! -f "$BACKEND_SOURCE" ]]; then
        echo "❌ Backend environment file not found."
        return 1
    fi

    mkdir -p "$SECRET_DIR"

    echo "[INFO] Encrypting backend environment..."

    sops -e \
        --filename-override "$SECRET_DIR/backend.env" \
        --input-type dotenv \
        --output "$BACKEND_SECRET" \
        "$BACKEND_SOURCE"

    chmod 600 "$BACKEND_SECRET"

    echo "✅ Backend environment encrypted."
}


encrypt_github_deploy_key() {
    if [[ ! -f "$DEPLOY_KEY_SOURCE" ]]; then
        echo "❌ GitHub deploy key not found: $DEPLOY_KEY_SOURCE"
        return 1
    fi

    mkdir -p "$SECRET_DIR"

    local temp_file
    temp_file="$(mktemp)"
    chmod 600 "$temp_file"

    if ! printf 'github_deploy_key_base64=%s\n' \
        "$(base64 -w 0 "$DEPLOY_KEY_SOURCE")" > "$temp_file"; then
        rm -f "$temp_file"
        echo "❌ Failed to prepare GitHub deploy key."
        return 1
    fi

    echo "[INFO] Encrypting GitHub deploy key..."

    if ! sops -e \
        --filename-override "$SECRET_DIR/github-deploy-key.env" \
        --input-type dotenv \
        --output "$DEPLOY_KEY_SECRET" \
        "$temp_file"; then
        rm -f "$temp_file"
        echo "❌ Failed to encrypt GitHub deploy key."
        return 1
    fi

    rm -f "$temp_file"
    chmod 600 "$DEPLOY_KEY_SECRET"

    echo "✅ GitHub deploy key encrypted."
}

encrypt_secrets() {
    encrypt_backend_env
    encrypt_github_deploy_key

    echo "✅ All sys_monitor secrets encrypted."
}


load_secrets() {
    if [[ ! -f "$BACKEND_SECRET" ]]; then
        echo "❌ Encrypted backend environment not found."
        echo "   Run: bash $MAIN_DIR/secrets.sh encrypt"
        return 1
    fi

    if [[ ! -f "$DEPLOY_KEY_SECRET" ]]; then
        echo "❌ Encrypted GitHub deploy key not found."
        echo "   Run: bash $MAIN_DIR/secrets.sh encrypt"
        return 1
    fi

    echo "[INFO] Loading encrypted sys_monitor secrets..."

    export TF_VAR_backend_env="$(
        sops -d \
            --input-type dotenv \
            --output-type dotenv \
            "$BACKEND_SECRET"
    )"

    local encoded_key

    encoded_key="$(
        sops -d \
            --input-type dotenv \
            --output-type dotenv \
            "$DEPLOY_KEY_SECRET" |
            sed -n 's/^github_deploy_key_base64=//p'
    )"

    if [[ -z "$encoded_key" ]]; then
        echo "❌ GitHub deploy key was not loaded."
        return 1
    fi

    export TF_VAR_github_deploy_key="$(
        printf '%s' "$encoded_key" | base64 -d
    )"

    if [[ -z "$TF_VAR_backend_env" ]]; then
        echo "❌ Backend environment is empty."
        return 1
    fi

    if [[ "$TF_VAR_github_deploy_key" != *"PRIVATE KEY"* ]]; then
        echo "❌ The decrypted deploy key does not appear to be a private key."
        return 1
    fi

    echo "✅ Sys_monitor secrets loaded into Terraform environment."
}


if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    case "${1:-}" in
        encrypt)
            encrypt_secrets
            ;;
        *)
            echo "Usage: bash $0 encrypt"
            exit 1
            ;;
    esac
fi
