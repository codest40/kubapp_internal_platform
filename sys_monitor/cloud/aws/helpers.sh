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


terraform_vars() {
    TF_VAR_account_id="$STATE_ACCOUNT_ID" \
    TF_VAR_kubapp_account_id="$KUBAPP_ACCOUNT_ID" \
    TF_VAR_env="$ENV" \
    TF_VAR_region="$REGION" \
    TF_VAR_profile="$STATE_PROFILE" \
    TF_VAR_cluster_mode="$CLUSTER_MODE" \
    TF_VAR_instance_type="$SYS_MONITOR_INSTANCE_TYPE" \
    TF_VAR_access_mode="$ACCESS_MODE" \
    TF_VAR_key_name="$SYS_MONITOR_KEY_NAME" \
    TF_VAR_ssh_cidr="${SSH_CIDR:-}" \
    terraform -chdir="$MAIN_DIR" "$@"
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

