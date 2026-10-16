#!/bin/bash

file_exists() {
    local file="$1"

    [[ -f "$file" ]]
}


file_is_missing() {
    local file="$1"

    [[ ! -f "$file" ]]
}


# =========================================================
# SOPS DETECTION
# =========================================================

is_sops_yaml() {
    local file="$1"

    grep -q '^sops:' "$file"
}


has_sops_dotenv_metadata() {
    local file="$1"

    grep -q '^sops_' "$file"
}


has_sops_metadata() {
    local file="$1"

    grep -qE '^(sops:|sops_)' "$file"
}


is_plaintext_file() {
    local file="$1"

    ! has_sops_metadata "$file"
}


# =========================================================
# FILE COMPARISON
# =========================================================
get_file_format() {
    local file="$1"

    # Backups retain the format of their original file.
    file="${file%.bak}"

    case "$file" in
        *.yaml|*.yml)
            echo "yaml"
            ;;
        *.env)
            echo "dotenv"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

files_match() {
    local file_a="$1"
    local file_b="$2"
    local format="${3:-}"

    if [[ -z "$format" ]]; then
        local format_a
        local format_b

        format_a=$(get_file_format "$file_a")
        format_b=$(get_file_format "$file_b")

        if [[ "$format_a" == "$format_b" ]]; then
            format="$format_a"
        fi
    fi

    if [[ "$format" == "yaml" ]]; then
        local json_a
        local json_b

        json_a=$(mktemp)
        json_b=$(mktemp)

        if ! yq -o=json "$file_a" > "$json_a"; then
            rm -f "$json_a" "$json_b"
            return 1
        fi

        if ! yq -o=json "$file_b" > "$json_b"; then
            rm -f "$json_a" "$json_b"
            return 1
        fi

        cmp -s "$json_a" "$json_b"
        local result=$?

        rm -f "$json_a" "$json_b"

        return "$result"
    fi

    if [[ "$format" == "dotenv" ]]; then
        local normalized_a
        local normalized_b

        normalized_a=$(mktemp)
        normalized_b=$(mktemp)

        if ! dotenv -f "$file_a" list | sort > "$normalized_a"; then
            rm -f "$normalized_a" "$normalized_b"
            return 1
        fi

        if ! dotenv -f "$file_b" list | sort > "$normalized_b"; then
            rm -f "$normalized_a" "$normalized_b"
            return 1
        fi

        cmp -s "$normalized_a" "$normalized_b"
        local result=$?

        rm -f "$normalized_a" "$normalized_b"

        return "$result"
    fi

    # Unknown files retain byte-for-byte comparison
    # until their format-specific comparison is implemented.
    cmp -s "$file_a" "$file_b"
}

files_differ() {
    local file_a="$1"
    local file_b="$2"

    ! cmp -s "$file_a" "$file_b"
}


# =========================================================
# BACKUP OPERATIONS
# =========================================================

backup_file() {
    local file="$1"
    local backup="${file}.bak"

    cp -f "$file" "$backup"

    echo "[INFO] Backup created: $backup"
}


# =========================================================
# SOPS DECRYPTION
# =========================================================

decrypt_to_temp() {
    local file="$1"
    local tmp="$2"

    echo "[INFO] Decrypting: $file"

    if ! sops -d "$file" > "$tmp"; then
        rm -f "$tmp"

        echo "[ERROR] ❌ Failed to decrypt:"
        echo "        $file"

        return 1
    fi
}


# =========================================================
# SOPS ENCRYPTION
# =========================================================

encrypt_from_file() {
    local source="$1"
    local target="$2"

    local tmp="${target}.tmp"

    echo "[INFO] Encrypting:"
    echo "       Source: $source"
    echo "       Target: $target"

    if ! sops --encrypt \
        --age "$AGE_PUBLIC_KEY" \
        --filename-override "$target" \
        "$source" > "$tmp"; then

        rm -f "$tmp"

        echo "[ERROR] ❌ Failed to encrypt:"
        echo "        $source"

        return 1
    fi

    mv -f "$tmp" "$target"

    echo "[INFO] Encryption complete: $target"
}


# =========================================================
# BACKUP VALIDATION
# =========================================================

validate_backup_source() {
    local backup="$1"

    echo "[INFO] Validating backup source:"
    echo "       $backup"

    # -----------------------------------------------------
    # BACKUP MUST EXIST
    # -----------------------------------------------------

    if ! file_exists "$backup"; then
        echo "[ERROR] ❌ Backup does not exist:"
        echo "        $backup"

        return 1
    fi

    # -----------------------------------------------------
    # PLAINTEXT BACKUP
    # -----------------------------------------------------

    if is_plaintext_file "$backup"; then
        echo "[INFO] Backup is plaintext"
        return 0
    fi

    # -----------------------------------------------------
    # SOPS YAML BACKUP
    # -----------------------------------------------------

    if is_sops_yaml "$backup"; then
        echo "[WARN] Backup contains SOPS YAML metadata"
        echo "[INFO] Attempting to restore plaintext backup"

        local tmp
        tmp=$(mktemp)

        if ! decrypt_to_temp "$backup" "$tmp"; then
            return 1
        fi

        mv -f "$tmp" "$backup"

        echo "[INFO] Backup restored to plaintext"

        return 0
    fi

    # -----------------------------------------------------
    # SOPS DOTENV-STYLE BACKUP
    # -----------------------------------------------------

    if has_sops_dotenv_metadata "$backup"; then
        echo "[WARN] Backup contains SOPS dotenv metadata"
        echo "[INFO] Backup is not automatically treated as decryptable"

        echo "[ERROR] ❌ Backup cannot be safely used as plaintext source:"
        echo "        $backup"

        return 1
    fi

    # -----------------------------------------------------
    # UNKNOWN STATE
    # -----------------------------------------------------

    echo "[ERROR] ❌ Backup state is unknown:"
    echo "        $backup"

    return 1
}


# =========================================================
# RECOVERY
# =========================================================

recover_backup_from_secret() {
    local file="$1"
    local backup="$2"

    echo "[WARN] Backup missing"
    echo "[INFO] Recovering plaintext backup from encrypted secret"

    local tmp
    tmp=$(mktemp)

    if ! decrypt_to_temp "$file" "$tmp"; then
        return 1
    fi

    mv -f "$tmp" "$backup"

    echo "[INFO] Backup recovered: $backup"
}


recreate_secret_from_backup() {
    local file="$1"
    local backup="$2"

    echo "[INFO] Recreating encrypted secret from backup"

    if ! validate_backup_source "$backup"; then
        return 1
    fi

    encrypt_from_file "$backup" "$file"

    echo "[INFO] Encrypted file recreated: $file"
}


# =========================================================
# RECONCILE: ENCRYPTED SECRET + VALID PLAINTEXT BACKUP
# =========================================================

reconcile_encrypted_secret() {
    local file="$1"
    local backup="$2"

    echo "[INFO] Secret is encrypted"
    echo "[INFO] Comparing decrypted secret against backup"

    local decrypted_tmp
    decrypted_tmp=$(mktemp)

    if ! decrypt_to_temp "$file" "$decrypted_tmp"; then
        return 1
    fi

    if files_match "$decrypted_tmp" "$backup" "$(get_file_format "$file")"; then
        rm -f "$decrypted_tmp"

        echo "[INFO] Encrypted file matches backup"
        echo "[INFO] Nothing to update"

        return 0
    fi

    rm -f "$decrypted_tmp"

    echo "[WARN] Backup differs from encrypted file"
    echo "[INFO] Using backup as the new plaintext source"

    encrypt_from_file "$backup" "$file"

    echo "[INFO] Encrypted file updated from backup"
}


# =========================================================
# RECONCILE: PLAINTEXT SECRET + VALID PLAINTEXT BACKUP
# =========================================================

reconcile_plaintext_secret() {
    local file="$1"
    local backup="$2"

    echo "[INFO] Secret is plaintext"

    if files_match "$file" "$backup"; then
        echo "[INFO] Plaintext secret matches backup"
    else
        echo "[WARN] Plaintext secret differs from backup"
        echo "[INFO] Using backup as the source"

        cp -f "$backup" "$file"
    fi

    echo "[INFO] Encrypting secret from backup"

    encrypt_from_file "$backup" "$file"

    echo "[INFO] Secret encrypted"
}


# =========================================================
# RECONCILE: BOTH FILES EXIST
# =========================================================

reconcile_both_exist() {
    local file="$1"
    local backup="$2"

    echo "[INFO] Both secret and backup exist"

    # -----------------------------------------------------
    # BACKUP MUST BE SAFE BEFORE IT CAN BE THE SOURCE
    # -----------------------------------------------------

    if ! validate_backup_source "$backup"; then
        echo "[ERROR] ❌ Backup validation failed"
        echo "[ERROR] Reconciliation stopped"

        return 1
    fi

    # -----------------------------------------------------
    # SECRET STATE
    # -----------------------------------------------------

    if has_sops_metadata "$file"; then
        reconcile_encrypted_secret "$file" "$backup"
        return
    fi

    reconcile_plaintext_secret "$file" "$backup"
}


# =========================================================
# RECONCILE: SECRET EXISTS, BACKUP MISSING
# =========================================================

reconcile_secret_only() {
    local file="$1"
    local backup="$2"

    echo "[WARN] Secret exists but backup is missing"

    # -----------------------------------------------------
    # ENCRYPTED SECRET
    # -----------------------------------------------------

    if has_sops_metadata "$file"; then
        recover_backup_from_secret "$file" "$backup"
        return
    fi

    # -----------------------------------------------------
    # PLAINTEXT SECRET
    # -----------------------------------------------------

    echo "[INFO] Secret is plaintext"
    echo "[INFO] Creating backup before encryption"

    backup_file "$file"

    echo "[INFO] Encrypting secret"

    encrypt_from_file "$backup" "$file"

    echo "[INFO] Secret encrypted"
}


# =========================================================
# RECONCILE: BACKUP EXISTS, SECRET MISSING
# =========================================================

reconcile_backup_only() {
    local file="$1"
    local backup="$2"

    echo "[WARN] Secret is missing but backup exists"

    recreate_secret_from_backup "$file" "$backup"
}


# =========================================================
# MAIN RECONCILIATION ORCHESTRATOR
# =========================================================

reconcile_encrypted_backup() {
    local file="$1"
    local backup="$2"

    echo "[INFO] Reconciling secret state"
    echo "       Secret: $file"
    echo "       Backup: $backup"

    # =====================================================
    # BOTH EXIST
    # =====================================================

    if file_exists "$file" && file_exists "$backup"; then
        reconcile_both_exist "$file" "$backup"
        return
    fi

    # =====================================================
    # SECRET EXISTS, BACKUP MISSING
    # =====================================================

    if file_exists "$file" && file_is_missing "$backup"; then
        reconcile_secret_only "$file" "$backup"
        return
    fi

    # =====================================================
    # SECRET MISSING, BACKUP EXISTS
    # =====================================================

    if file_is_missing "$file" && file_exists "$backup"; then
        reconcile_backup_only "$file" "$backup"
        return
    fi

    # =====================================================
    # NEITHER EXISTS
    # =====================================================

    echo "[ERROR] ❌ Neither secret nor backup exists"
    echo "        Secret: $file"
    echo "        Backup: $backup"

    return 1
}


# =========================================================
# TOP-LEVEL SECRET PROCESSOR
# =========================================================

process_secret_file() {
    local file="$1"
    local backup="${file}.bak"

    echo "[INFO] Processing: $file"

    reconcile_encrypted_backup "$file" "$backup"
}
