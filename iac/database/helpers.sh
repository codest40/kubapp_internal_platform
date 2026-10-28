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

    actual_account="$(
        aws sts get-caller-identity \
            --query Account \
            --output text
    )"

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


terraform_init() {
    local dir="$1"
    terraform -chdir="$dir" init
}


terraform_validate() {
    local dir="$1"

    terraform -chdir="$dir" fmt
    terraform -chdir="$dir" validate
}

validate_assume() {
    if [[ "$DATABASE_MODE" != "cross" ]]; then
      echo "Local Mode Detected; Aborting Attempt to Creat Assume Role..."
      return 1
    fi
    return 0
}

encrypt_setup_env() {
    local input="$DATABASE_DIR/setup.env"
    local output="$DATABASE_DIR/store/secrets/setup.env.enc"

    if [[ ! -f "$input" ]]; then
        echo "❌ setup.env not found: $input"
        return 1
    fi

    echo "Encrypting database setup configuration..."

    if ! sops -e \
        --filename-override "$DATABASE_DIR/store/secrets/setup.env" \
        --input-type dotenv \
        --output "$output" \
        "$input"; then

        echo "❌ Failed to encrypt setup.env"
        return 1
    fi

    echo "✅ setup.env encrypted"
    echo "   Output: $output"
}

decrypt_setup_env() {
    local input="$DATABASE_DIR/store/secrets/setup.env.enc"
    local output="$DATABASE_DIR/setups.env"

    if [[ ! -f "$input" ]]; then
        echo "❌ Encrypted setup file not found: $input"
        return 1
    fi

    echo "Decrypting database setup configuration..."

    if ! sops -d \
        --input-type dotenv \
        --output-type dotenv \
        "$input" \
        > "$output"; then

        rm -f "$output"

        echo "❌ Failed to decrypt setup.env"
        return 1
    fi

    echo "✅ setups.env file decrypted"
}
