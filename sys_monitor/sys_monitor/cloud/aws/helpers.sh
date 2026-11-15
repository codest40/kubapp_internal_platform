#!/usr/bin/env bash

line() {
    echo "======================================================================"
}


set_aws_profile() {
    local profile="$1"

    export AWS_PROFILE="$profile"
    echo "AWS PROFILE: $AWS_PROFILE"
}


check_aws() {
    echo "Checking AWS identity..."

    local actual_account

    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        echo "❌ AWS credentials failed validation."
        echo "   Profile: $AWS_PROFILE"
        return 1
    fi

    actual_account="$(aws sts get-caller-identity \
        --query Account \
        --output text)"

    if [[ "$actual_account" != "$STATE_ACCOUNT_ID" ]]; then
        echo "❌ AWS account mismatch."
        echo "   Expected: $STATE_ACCOUNT_ID"
        echo "   Actual:   $actual_account"
        return 1
    fi

    echo "✅ AWS credentials valid."
    echo "✅ AWS account confirmed: $actual_account"
}


check_directories() {
    local dir

    for dir in "$@"; do
        if [[ ! -d "$dir" ]]; then
            echo "❌ Required directory not found: $dir"
            return 1
        fi
    done
}

detect_cluster_mode() {
  if [[ "$CLUSTER_MODE" == "local" ]]; then
    echo "local"
  else
    echo "cross"
  fi

}

update_status() {
    local status="${1:-}"
    local file="$AWS_DIR/store/status"
    local mode

    if [[ "$status" != "active" && "$status" != "inactive" ]]; then
        echo "❌ Invalid status: $status"
        echo "   Expected: active or inactive"
        return 1
    fi

    mode="$(detect_cluster_mode)"
    if [[ "$mode" == "local" ]]; then
      status="inactive"
    fi

    mkdir -p "$(dirname "$file")"
    printf '%s\n' "$status" > "$file"
    echo "✅ Status updated: $file → $status"
}


terraform_has_state() {
    local dir="$1"

    terraform -chdir="$dir" state list 2>/dev/null | grep -q .
}

tf_needed_vars() {
    local name value
    local all_vars=()
    while IFS='=' read -r name value; do
        [[ -z "$name" || "$name" == \#* ]] && continue
        name="${name#SYS_MONITOR_}"
        name="${name,,}"
        all_vars+=("TF_VAR_${name}=${value}")
    done < "$SETUP_ENV"
    all_vars+=("TF_VAR_profile=$STATE_PROFILE")
    all_vars+=("TF_VAR_ssh_cidr=${SSH_CIDR:-}")
    env "${all_vars[@]}" terraform -chdir="$MAIN_DIR" "$@"
}

terraform_vars() {
    tf_needed_vars "$@"
}

terraform_init() {
    local dir="$1"

    terraform -chdir="$dir" init -reconfigure
}


terraform_validate() {
    local dir="$1"

    terraform -chdir="$dir" fmt -recursive
    terraform -chdir="$dir" validate
}


encrypt_setup_env() {
    local input="$AWS_DIR/setup.env"
    local output="$STORE_DIR/secrets/setup.env.enc"

    if [[ ! -f "$input" ]]; then
        echo "ERROR: setup.env not found: $input"
        return 1
    fi

    mkdir -p "$(dirname "$output")"

    echo "Encrypting sys_monitor configuration..."

    if ! sops -e \
        --filename-override "$STORE_DIR/secrets/setup.env" \
        --input-type dotenv \
        --output "$output" \
        "$input"; then

        echo "ERROR: Failed to encrypt setup.env"
        return 1
    fi

    echo "setup.env encrypted."
    echo "Output: $output"
}


decrypt_setup_env() {
    local input="$STORE_DIR/secrets/setup.env.enc"
    local output="$AWS_DIR/setup.tmp.env"

    if [[ ! -f "$input" ]]; then
        echo "ERROR: Encrypted setup file not found: $input"
        return 1
    fi

    echo "Decrypting sys_monitor configuration..."

    if ! sops -d \
        --input-type dotenv \
        --output-type dotenv \
        "$input" > "$output"; then

        rm -f "$output"
        echo "ERROR: Failed to decrypt setup.env"
        return 1
    fi
    echo "Configuration decrypted."
}
