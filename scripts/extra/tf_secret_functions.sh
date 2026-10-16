#!/usr/bin/env bash

# =========================================================
# ENCRYPT TERRAFORM TFVARS WHEN NECESSARY
# =========================================================

tf_encrypt_file() {
    local tfvars="$1"
    local encrypted="${tfvars}.enc"
    local decrypted_tmp=""
    local encrypted_tmp=""

    echo "[INFO] Checking: ${tfvars#$ROOT/}"

    # Compare the existing encrypted file with the plaintext.
    if [[ -f "$encrypted" ]]; then
        decrypted_tmp="$(mktemp --suffix=.tfvars)" || {
            echo "[ERROR] Cannot create temporary TFVars file"
            return 1
        }

        if ! sops --decrypt "$encrypted" > "$decrypted_tmp"; then
            rm -f -- "$decrypted_tmp"
            echo "[ERROR] Failed to decrypt: ${encrypted#$ROOT/}"
            return 1
        fi

        if cmp -s "$tfvars" "$decrypted_tmp"; then
            rm -f -- "$decrypted_tmp"
            echo "[INFO] Encrypted file is up to date"
            return 0
        fi

        rm -f -- "$decrypted_tmp"
        decrypted_tmp=""

        echo "[INFO] Encrypted content differs; re-encryption required"
    else
        echo "[INFO] Encrypted file does not exist"
    fi

    # Encrypt into a temporary file so a failure cannot destroy
    # the existing encrypted file.
    encrypted_tmp="$(mktemp --suffix=.enc)" || {
        echo "[ERROR] Cannot create temporary encrypted file"
        return 1
    }

    if ! sops --encrypt \
        --age "$AGE_PUBLIC_KEY" \
        --filename-override="${tfvars#"$ROOT"/}" \
        "$tfvars" > "$encrypted_tmp"; then
        rm -f -- "$encrypted_tmp"
        echo "[ERROR] Failed to encrypt: ${tfvars#$ROOT/}"
        return 1
    fi

    # Verify that the encrypted output decrypts to the exact source.
    decrypted_tmp="$(mktemp --suffix=.tfvars)" || {
        rm -f -- "$encrypted_tmp"
        echo "[ERROR] Cannot create verification file"
        return 1
    }

    if ! sops --decrypt "$encrypted_tmp" > "$decrypted_tmp"; then
        rm -f -- "$encrypted_tmp" "$decrypted_tmp"
        echo "[ERROR] Failed to decrypt newly encrypted output"
        return 1
    fi

    if ! cmp -s "$tfvars" "$decrypted_tmp"; then
        rm -f -- "$encrypted_tmp" "$decrypted_tmp"
        echo "[ERROR] Encrypted output differs from source"
        return 1
    fi

    rm -f -- "$decrypted_tmp"

    if ! mv -f -- "$encrypted_tmp" "$encrypted"; then
        rm -f -- "$encrypted_tmp"
        echo "[ERROR] Failed to replace encrypted file"
        return 1
    fi

    echo "[INFO] Encryption and verification successful"
}

# =========================================================
# SYNCHRONIZE ROOT TFVARS WITH RUNTIME TFVARS
# =========================================================

tf_select_env_tfvars() {
    local stack="$1"
    local env="$2"

    local stack_dir="$ROOT/iac/$stack"
    local env_dir="$stack_dir/envs/$env"
    local root_file="$stack_dir/terraform.tfvars"
    local env_file="$env_dir/${stack}.tfvars"

    # Skip stacks that have neither a root source nor a runtime file.
    if [[ ! -f "$root_file" && ! -f "$env_file" ]]; then
        echo "[INFO] No TFVars found for $stack/$env; skipping"
        return 0
    fi

    # The root file is authoritative when it exists.
    if [[ -f "$root_file" ]]; then
        if [[ -f "$env_file" ]]; then
            if cmp -s "$root_file" "$env_file"; then
                echo "[INFO] Root and runtime TFVars match; no copy needed"
            else
                echo "[INFO] Root and runtime TFVars differ; updating runtime file"

                cp -- "$root_file" "$env_file" || {
                    echo "[ERROR] Failed to update ${env_file#$ROOT/}"
                    return 1
                }
            fi
        else
            echo "[INFO] Runtime TFVars missing; creating it from root source"

            mkdir -p -- "$env_dir" || {
                echo "[ERROR] Failed to create environment directory"
                return 1
            }

            cp -- "$root_file" "$env_file" || {
                echo "[ERROR] Failed to create ${env_file#$ROOT/}"
                return 1
            }
        fi
    else
        echo "[INFO] No root terraform.tfvars; retaining runtime file"
    fi

    # Encrypt only the runtime file used by GitHub Actions.
    if [[ -f "$env_file" ]]; then
        tf_encrypt_file "$env_file" || return 1
    fi
}

# =========================================================
# TERRAFORM SECRETS ENTRY POINT
# =========================================================

encrypt_tf_secrets() {
    local env="${1:-dev}"
    local stack
    local stack_dir

    case "$env" in
        dev|prod)
            ;;
        *)
            echo "[ERROR] Invalid Terraform environment: $env"
            echo "[ERROR] Supported environments: dev, prod"
            return 1
            ;;
    esac

    if [[ -z "${ROOT:-}" || ! -d "$ROOT/iac" ]]; then
        echo "[ERROR] Invalid or missing project root"
        return 1
    fi

    if [[ -z "${AGE_PUBLIC_KEY:-}" ]]; then
        echo "[ERROR] AGE_PUBLIC_KEY is not configured"
        return 1
    fi

    if [[ ! ${STACKS+x} ]]; then
        echo "[ERROR] STACKS is not configured"
        return 1
    fi

    echo
    echo "=================================================="
    echo "[INFO] TERRAFORM SECRETS"
    echo "[INFO] ENVIRONMENT: $env"
    echo "=================================================="

    for stack in "${STACKS[@]}"; do
        stack_dir="$ROOT/iac/$stack"

        if [[ ! -d "$stack_dir" ]]; then
            echo "[WARN] Stack directory not found: $stack_dir"
            continue
        fi

        echo
        echo "--------------------------------------------------"
        echo "[INFO] STACK: $stack"
        echo "--------------------------------------------------"

        tf_select_env_tfvars "$stack" "$env" || {
            echo "[ERROR] Failed to process $stack/$env"
            return 1
        }
    done

    echo
    echo "[INFO] Terraform secrets processing complete"
}
