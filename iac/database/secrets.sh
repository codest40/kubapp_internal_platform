#!/usr/bin/env bash

set -euo pipefail

SECRET_FILE="$DATABASE_DIR/store/secrets/database-secret.env"

if [[ ! -f "$SECRET_FILE" ]]; then
    echo "❌ Database secret file not found: $SECRET_FILE"
    exit 1
fi

echo "[INFO] Loading database secrets"
while IFS='=' read -r key value; do
    case "$key" in
        master_username)
            export TF_VAR_master_username="$value"
            ;;
        master_password)
            export TF_VAR_master_password="$value"
            ;;
    esac
done < <(sops -d "$SECRET_FILE")

: "${TF_VAR_master_username:?❌ master_username not loaded}"
: "${TF_VAR_master_password:?❌ master_password not loaded}"

echo "[INFO] Database secrets loaded"
