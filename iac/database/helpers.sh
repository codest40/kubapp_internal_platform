#!/usr/bin/env bash

line() {
    echo "======================================================================"
}


set_aws_profile() {
    local profile="$1"
    export AWS_PROFILE="$profile"
    echo "AWS PROFILE: $AWS_PROFILE"
}


# Temporary AWS profile state.
KUBAPP_TMP_AWS_CONFIG=""
KUBAPP_TMP_AWS_BACKUP=""
KUBAPP_TMP_AWS_CONFIG_EXISTED=false

create_tmp_role() {
    if [[ "${GITHUB_ACTIONS:-false}" != "true" || "$DATABASE_MODE" != "cross" ]]; then
        return 0
    fi

    local dir="$HOME/.aws"
    local config="$dir/config"

    mkdir -p "$dir"

    KUBAPP_TMP_AWS_CONFIG="$config"
    KUBAPP_TMP_AWS_BACKUP="${config}.kubapp-backup.$$"

    # Preserve the existing AWS configuration.
    if [[ -f "$config" ]]; then
        cp -p "$config" "$KUBAPP_TMP_AWS_BACKUP"
        KUBAPP_TMP_AWS_CONFIG_EXISTED=true
    else
        KUBAPP_TMP_AWS_CONFIG_EXISTED=false
    fi

    # This profile assumes the database account role.
    # Terraform handles the subsequent KUBAPP cross-account role.
    cat > "$config" <<EOF
[profile database-cross]
role_arn = arn:aws:iam::${STATE_ACCOUNT_ID}:role/db-terraform-role
credential_source = Environment
region = ${REGION}
output = json
EOF

    echo "Temporary database-account AWS profile created."
    echo "   Profile: database-cross"
    echo "   Role: arn:aws:iam::${STATE_ACCOUNT_ID}:role/db-terraform-role"
    export AWS_CONFIG_FILE="$config"
}


delete_tmp_role() {
    if [[ "${GITHUB_ACTIONS:-false}" != "true" || "$DATABASE_MODE" != "cross" ]]; then
        return 0
    fi

    if [[ -z "$KUBAPP_TMP_AWS_CONFIG" ]]; then
        return 0
    fi

    if [[ "$KUBAPP_TMP_AWS_CONFIG_EXISTED" == "true" ]]; then
        if [[ -f "$KUBAPP_TMP_AWS_BACKUP" ]]; then
            mv "$KUBAPP_TMP_AWS_BACKUP" "$KUBAPP_TMP_AWS_CONFIG"
        fi
    else
        rm -f "$KUBAPP_TMP_AWS_CONFIG"
    fi

    KUBAPP_TMP_AWS_CONFIG=""
    KUBAPP_TMP_AWS_BACKUP=""
    KUBAPP_TMP_AWS_CONFIG_EXISTED=false
}


diagnose_role() {
    echo "=== GITHUB SOURCE IDENTITY ==="
    aws sts get-caller-identity

    if [[ "${GITHUB_ACTIONS:-false}" != "true" || "$DATABASE_MODE" != "cross" ]]; then
        return 0
    fi

    echo "=== DATABASE ACCOUNT ROLE VALIDATION ==="
    local actual_arn
    local expected_account="$STATE_ACCOUNT_ID"
    if ! actual_arn=$(
        env -u AWS_PROFILE aws --profile database-cross sts get-caller-identity \
            --query Arn \
            --output text
    ); then
        echo "ERROR: Failed to assume db-terraform-role."
        return 1
    fi

    echo "Expected account: $expected_account"
    echo "Actual identity:  $actual_arn"

    if [[ "$actual_arn" != *":assumed-role/db-terraform-role/"* ]]; then
        echo "ERROR: database-cross did not assume db-terraform-role."
        return 1
    fi
    echo "Database account role assumption successful."
}

assume_github_role() {
    local role_arn="arn:aws:iam::${STATE_ACCOUNT_ID}:role/${GITHUB_ROLE}"
    local session_name="kubapp-${GITHUB_RUN_ID:-database}"

    echo "Assuming AWS account through GitHub OIDC..."
    echo "Role: $role_arn"

    : "${ACTIONS_ID_TOKEN_REQUEST_TOKEN:?GitHub OIDC token request token unavailable}"
    : "${ACTIONS_ID_TOKEN_REQUEST_URL:?GitHub OIDC token request URL unavailable}"

    local oidc_response
    local oidc_token
    local credentials

    oidc_response=$(curl -fsS \
        -H "Authorization: Bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
        "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=sts.amazonaws.com") || {
        echo "ERROR: Failed to obtain GitHub OIDC token."
        return 1
    }

    oidc_token=$(jq -er '.value' <<< "$oidc_response") || {
        echo "ERROR: Invalid GitHub OIDC token response."
        return 1
    }

    # Remove existing AWS credentials before obtaining OIDC credentials.
    unset AWS_ACCESS_KEY_ID
    unset AWS_SECRET_ACCESS_KEY
    unset AWS_SESSION_TOKEN
    unset AWS_SECURITY_TOKEN
    unset AWS_PROFILE

    echo "Requesting temporary AWS credentials from STS..."

    credentials=$(aws sts assume-role-with-web-identity \
        --role-arn "$role_arn" \
        --role-session-name "$session_name" \
        --web-identity-token "$oidc_token" \
        --duration-seconds 3600) || {
        echo "ERROR: AWS STS authentication failed."
        return 1
    }

    AWS_ACCESS_KEY_ID=$(jq -er '.Credentials.AccessKeyId' <<< "$credentials") || return 1
    AWS_SECRET_ACCESS_KEY=$(jq -er '.Credentials.SecretAccessKey' <<< "$credentials") || return 1
    AWS_SESSION_TOKEN=$(jq -er '.Credentials.SessionToken' <<< "$credentials") || return 1

    export AWS_ACCESS_KEY_ID
    export AWS_SECRET_ACCESS_KEY
    export AWS_SESSION_TOKEN

    unset oidc_token oidc_response credentials

    echo "GitHub OIDC authentication successful."
}


check_aws() {
    echo "Checking AWS identity..."

    local actual_account

    actual_account=$(
        aws sts get-caller-identity \
            --query Account \
            --output text 2>/dev/null
    ) || actual_account=""

    # Check whether the current credentials already belong to the target account.
    if [[ "$actual_account" != "$STATE_ACCOUNT_ID" ]]; then

        echo "AWS account mismatch."
        echo "   Expected: $STATE_ACCOUNT_ID"
        echo "   Actual:   ${actual_account:-Unavailable}"

        if [[ "${GITHUB_ACTIONS:-false}" != "true" ]]; then
            echo "ERROR: Local AWS account mismatch."
            echo "Profile: $STATE_PROFILE"
            return 1
        fi

        echo "GitHub Actions detected. Switching AWS identity..."

        assume_github_role || return 1

        # Verify GitHub OIDC source identity.
        actual_account=$(
            aws sts get-caller-identity \
                --query Account \
                --output text
        ) || {
            echo "ERROR: Unable to validate assumed AWS credentials."
            return 1
        }

        if [[ "$actual_account" != "$STATE_ACCOUNT_ID" ]]; then
            echo "ERROR: AWS account mismatch after authentication."
            echo "Expected: $STATE_ACCOUNT_ID"
            echo "Actual:   $actual_account"
            return 1
        fi

        echo "GitHub AWS identity confirmed: $actual_account"

    else
        echo "AWS account confirmed: $actual_account"
    fi

    # On GitHub, we create and validate the database account profile.
    # Even when the initial AWS identity was already correct.
    if [[ "${GITHUB_ACTIONS:-false}" == "true" && "$DATABASE_MODE" == "cross" ]]; then
        create_tmp_role
        diagnose_role || return 1
    fi

    echo "AWS credentials validated successfully."
}


check_directories() {
    local dir

    for dir in "$@"; do
        if [[ ! -d "$dir" ]]; then
            echo "ERROR: Required directory not found: $dir"
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
        echo "Local Mode Detected; Aborting Attempt to Create Assume Role..."
        return 1
    fi

    return 0
}


encrypt_setup_env() {
    local input="$DATABASE_DIR/setup.env"
    local output="$DATABASE_DIR/store/secrets/setup.env.enc"

    if [[ ! -f "$input" ]]; then
        echo "ERROR: setup.env not found: $input"
        return 1
    fi

    echo "Encrypting database setup configuration..."
    if ! sops -e \
        --filename-override "$DATABASE_DIR/store/secrets/setup.env" \
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
    local input="$DATABASE_DIR/store/secrets/setup.env.enc"
    local output="$DATABASE_DIR/setups.env"

    if [[ ! -f "$input" ]]; then
        echo "ERROR: Encrypted setup file not found: $input"
        return 1
    fi

    echo "Decrypting database setup configuration..."

    if ! sops -d \
        --input-type dotenv \
        --output-type dotenv \
        "$input" \
        > "$output"; then

        rm -f "$output"

        echo "ERROR: Failed to decrypt setup.env"
        return 1
    fi

    echo "setups.env file decrypted."
}


tf_needed_vars() {
    local name
    local value

    while IFS= read -r name; do
        [[ -z "$name" ]] && continue

        value="${!name}"
        export "TF_VAR_${name,,}=$value"

    done < <(
        sed -nE 's/^[[:space:]]*([A-Z][A-Z0-9_]*)[[:space:]]*=.*/\1/p' \
            "$DATABASE_DIR/setup.env"
    )
}
