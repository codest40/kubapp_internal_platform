#!/usr/bin/env bash

set -euo pipefail

ACTION="${1:-plan}"
AUTO="${2:-false}"
AUTO2=("-Y" "-Yes" "Yes")

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[[ -z "$ROOT" ]] && echo "❌ Unable to determine project root." && exit 1

for each in "${AUTO2[@]}"; do
    if [[ "${AUTO,,}" == "${each,,}" ]]; then
        AUTO="true"
        break
    fi
done

AWS_DIR="$ROOT/sys_monitor/cloud/aws"
SETUP_ENV="$AWS_DIR/setup.env"
HELPERS="$AWS_DIR/helpers.sh"
INIT_TF="$AWS_DIR/init_tf.sh"
PROVIDER="$AWS_DIR/manage_provider.sh"
BOOTSTRAP_DIR="$AWS_DIR/bootstrap"
IDENTITY_ROOT="$BOOTSTRAP_DIR/identity"
MAIN_DIR="$AWS_DIR/main"
STORE_DIR="$AWS_DIR/store"

for file in "$SETUP_ENV" "$HELPERS" "$INIT_TF" "$PROVIDER"; do
    if [[ ! -f "$file" ]]; then
        echo "❌ Required file not found: $file"
        exit 1
    fi
done

source "$SETUP_ENV"
source "$HELPERS"

validate_config() {
    : "${ENV:?❌ ENV is required}"
    : "${CLUSTER_MODE:?❌ CLUSTER_MODE is required}"
    : "${SYS_MONITOR_ACCOUNT_ID:?❌ SYS_MONITOR_ACCOUNT_ID is required}"
    : "${KUBAPP_ACCOUNT_ID:?❌ KUBAPP_ACCOUNT_ID is required}"
    : "${PROFILE_LOCAL:?❌ PROFILE_LOCAL is required}"
    : "${PROFILE_CROSS:?❌ PROFILE_CROSS is required}"
    : "${REGION:?❌ REGION is required}"
    : "${SYS_MONITOR_INSTANCE_TYPE:?❌ SYS_MONITOR_INSTANCE_TYPE is required}"
    : "${ACCESS_MODE:?❌ ACCESS_MODE is required}"
    : "${SYS_MONITOR_KEY_NAME:?❌ SYS_MONITOR_KEY_NAME is required}"

    if [[ "$CLUSTER_MODE" != "local" && "$CLUSTER_MODE" != "cross" ]]; then
        echo "❌ Invalid CLUSTER_MODE: $CLUSTER_MODE"
        echo "   Expected: local or cross"
        exit 1
    fi
}


derive_config() {
    if [[ "$CLUSTER_MODE" == "local" ]]; then
        STATE_ACCOUNT_ID="$KUBAPP_ACCOUNT_ID"
        STATE_PROFILE="$PROFILE_LOCAL"
        IDENTITY_DIR="$IDENTITY_ROOT/local"
    else
        STATE_ACCOUNT_ID="$SYS_MONITOR_ACCOUNT_ID"
        STATE_PROFILE="$PROFILE_CROSS"
        IDENTITY_DIR="$IDENTITY_ROOT/cross"
    fi

    STATE_BUCKET="kubapp-sys-monitor-${STATE_ACCOUNT_ID}"
    STATE_KEY="$ENV/sys-monitor-runtime/tf-state"

    export AWS_PROFILE="$STATE_PROFILE"
}


show_config() {
    line
    echo "SYS_MONITOR"
    line
    echo "ACTION       : $ACTION"
    echo "CLUSTER MODE : $CLUSTER_MODE"
    echo "ACCOUNT      : $STATE_ACCOUNT_ID"
    echo "PROFILE      : $STATE_PROFILE"
    echo "REGION       : $REGION"
    echo "STATE BUCKET : $STATE_BUCKET"
    echo "STATE KEY    : $STATE_KEY"
    echo "MAIN DIR     : $MAIN_DIR"
    echo "IDENTITY DIR : $IDENTITY_DIR"
    line
}


run_identity() {
    line
    echo "BOOTSTRAP: IDENTITY"
    line

    terraform_init "$IDENTITY_DIR"
    terraform_validate "$IDENTITY_DIR"

    if [[ "$CLUSTER_MODE" == "cross" ]]; then
        terraform -chdir="$IDENTITY_DIR" plan \
            -var="profile=$STATE_PROFILE" \
            -var="account_id=$STATE_ACCOUNT_ID" \
            -var="kubapp_account_id=$KUBAPP_ACCOUNT_ID" \
            -var="access_mode=$ACCESS_MODE" \
            -var="region=$REGION"

        terraform -chdir="$IDENTITY_DIR" apply \
            --auto-approve \
            -var="profile=$STATE_PROFILE" \
            -var="account_id=$STATE_ACCOUNT_ID" \
            -var="kubapp_account_id=$KUBAPP_ACCOUNT_ID" \
            -var="access_mode=$ACCESS_MODE" \
            -var="region=$REGION"
    else
        terraform -chdir="$IDENTITY_DIR" plan \
            -var="profile=$STATE_PROFILE" \
            -var="access_mode=$ACCESS_MODE" \
            -var="region=$REGION"

        terraform -chdir="$IDENTITY_DIR" apply \
            --auto-approve \
            -var="profile=$STATE_PROFILE" \
            -var="access_mode=$ACCESS_MODE" \
            -var="region=$REGION"
    fi

    echo "✅ Identity bootstrap complete."
}


destroy_identity() {
    line
    echo "DESTROY: IDENTITY"
    line

    terraform_init "$IDENTITY_DIR"

    if ! terraform_has_state "$IDENTITY_DIR"; then
        echo "ℹ️  Identity state has no managed resources. Skipping."
        return 0
    fi

    terraform_validate "$IDENTITY_DIR"

    if [[ "$CLUSTER_MODE" == "cross" ]]; then
        terraform -chdir="$IDENTITY_DIR" plan -destroy \
            -var="profile=$STATE_PROFILE" \
            -var="account_id=$STATE_ACCOUNT_ID" \
            -var="kubapp_account_id=$KUBAPP_ACCOUNT_ID" \
            -var="access_mode=$ACCESS_MODE" \
            -var="region=$REGION"

        terraform -chdir="$IDENTITY_DIR" destroy \
            --auto-approve \
            -var="profile=$STATE_PROFILE" \
            -var="account_id=$STATE_ACCOUNT_ID" \
            -var="kubapp_account_id=$KUBAPP_ACCOUNT_ID" \
            -var="access_mode=$ACCESS_MODE" \
            -var="region=$REGION"
    else
        terraform -chdir="$IDENTITY_DIR" plan -destroy \
            -var="profile=$STATE_PROFILE" \
            -var="access_mode=$ACCESS_MODE" \
            -var="region=$REGION"

        terraform -chdir="$IDENTITY_DIR" destroy \
            --auto-approve \
            -var="profile=$STATE_PROFILE" \
            -var="access_mode=$ACCESS_MODE" \
            -var="region=$REGION"
    fi

    echo "✅ Identity bootstrap destroyed."
}


activate_provider() {
    source "$PROVIDER"
    manage_provider "$CLUSTER_MODE"
}


run_init() {
    line
    echo "TERRAFORM INIT: MAIN"
    line

    terraform -chdir="$MAIN_DIR" init -reconfigure \
        -backend-config="bucket=$STATE_BUCKET" \
        -backend-config="key=$STATE_KEY" \
        -backend-config="region=$REGION" \
        -backend-config="profile=$STATE_PROFILE"
}


run_plan() {
    activate_provider
    run_init
    terraform_validate "$MAIN_DIR"
    terraform_vars plan
}


run_apply() {
    activate_provider
    run_init
    terraform_validate "$MAIN_DIR"
    terraform_vars plan

    if terraform_vars apply --auto-approve; then
        echo "✅ APPLY complete."
        update_status "active"
    else
        echo "❌ APPLY failed."
        update_status "inactive"
        return 1
    fi
}


run_destroy() {
    if [[ "$AUTO" != "true" ]]; then
        echo
        echo "⚠️  This will destroy the sys_monitor runtime Terraform resources."
        echo
        echo "Account : $STATE_ACCOUNT_ID"
        echo "Profile : $STATE_PROFILE"
        echo "Mode    : $CLUSTER_MODE"
        echo

        read -rp "Type 'yes' to continue: " CONFIRM

        if [[ "$CONFIRM" != "yes" ]]; then
            echo "❌ Destroy cancelled."
            return 1
        fi
    fi

    activate_provider
    run_init
    terraform_validate "$MAIN_DIR"

    terraform_vars plan -destroy

    if terraform_vars destroy --auto-approve; then
        echo "✅ DESTROY complete."
        update_status "inactive"
    else
        echo "❌ DESTROY failed."
        update_status "active"
        return 1
    fi
}


apply() {
    run_identity
    #"$INIT_TF" apply
    run_apply
}


plan() {
    run_identity
    run_plan
}


destroy() {
    run_destroy
    destroy_identity
    #"$INIT_TF" apply
}


validate_config
derive_config
show_config

check_directories \
    "$BOOTSTRAP_DIR" \
    "$IDENTITY_DIR" \
    "$MAIN_DIR" \
    "$STORE_DIR"

check_aws


case "$ACTION" in
    apply)
        apply
        ;;
    plan)
        plan
        ;;
    destroy)
        destroy
        ;;
    *)
        echo "❌ Unknown action: $ACTION"
        echo
        echo "Usage:"
        echo "  ./runner.sh apply"
        echo "  ./runner.sh plan"
        echo "  ./runner.sh destroy"
        echo "  ./runner.sh destroy -y"
        exit 1
        ;;
esac
