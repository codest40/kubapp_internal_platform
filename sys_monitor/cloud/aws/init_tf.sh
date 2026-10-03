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

STATE_DIR="$AWS_DIR/bootstrap/state"
BUCKET_DIR="$STATE_DIR/bucket"
CROSS_DIR="$STATE_DIR/cross"
LOCAL_DIR="$STATE_DIR/local"
RUNTIME_DIR="$STATE_DIR/runtime"

if [[ ! -f "$SETUP_ENV" ]]; then
    echo "❌ setup.env not found: $SETUP_ENV"
    exit 1
fi

if [[ ! -f "$HELPERS" ]]; then
    echo "❌ helpers.sh not found: $HELPERS"
    exit 1
fi

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
        ACTIVE_STATE_DIR="$LOCAL_DIR"
        ACTIVE_STATE_KEY="$ENV/sys-monitor-local/tf-state"
    else
        STATE_ACCOUNT_ID="$SYS_MONITOR_ACCOUNT_ID"
        STATE_PROFILE="$PROFILE_CROSS"
        ACTIVE_STATE_DIR="$CROSS_DIR"
        ACTIVE_STATE_KEY="$ENV/sys-monitor-cross/tf-state"
    fi

    STATE_BUCKET="kubapp-sys-monitor-${STATE_ACCOUNT_ID}"

    export AWS_PROFILE="$STATE_PROFILE"
}


show_config() {
    line
    echo "STATE BOOTSTRAP"
    line
    echo "CLUSTER MODE : $CLUSTER_MODE"
    echo "ACTION       : $ACTION"
    echo "ACCOUNT      : $STATE_ACCOUNT_ID"
    echo "PROFILE      : $STATE_PROFILE"
    echo "REGION       : $REGION"
    echo "BUCKET       : $STATE_BUCKET"
    echo "ACTIVE STATE : $ACTIVE_STATE_KEY"
    echo "RUNTIME STATE: $ENV/sys-monitor-runtime/tf-state"
    line
}


bootstrap_bucket() {
    line
    echo "BOOTSTRAP: STATE BUCKET"
    line

    terraform_init "$BUCKET_DIR"
    terraform_validate "$BUCKET_DIR"

    terraform -chdir="$BUCKET_DIR" plan \
        -var="account_id=$STATE_ACCOUNT_ID" \
        -var="region=$REGION"

    terraform -chdir="$BUCKET_DIR" apply \
        --auto-approve \
        -var="account_id=$STATE_ACCOUNT_ID" \
        -var="region=$REGION"

    echo "✅ State bucket ready: $STATE_BUCKET"
}


bootstrap_state() {
    local name="$1"
    local dir="$2"
    local key="$3"

    line
    echo "BOOTSTRAP: $name STATE"
    line

    echo "Bucket : $STATE_BUCKET"
    echo "Key    : $key"
    echo "Profile: $STATE_PROFILE"
    echo

    terraform_init "$dir"
    terraform_validate "$dir"

    terraform -chdir="$dir" plan \
        -var="bucket=$STATE_BUCKET" \
        -var="env=$ENV" \
        -var="region=$REGION"

    terraform -chdir="$dir" apply \
        --auto-approve \
        -var="bucket=$STATE_BUCKET" \
        -var="env=$ENV" \
        -var="region=$REGION"

    echo "✅ $name state ready: $key"
}


bootstrap_active_state() {
    if [[ "$CLUSTER_MODE" == "local" ]]; then
        bootstrap_state \
            "LOCAL" \
            "$LOCAL_DIR" \
            "$ACTIVE_STATE_KEY"
    else
        bootstrap_state \
            "CROSS" \
            "$CROSS_DIR" \
            "$ACTIVE_STATE_KEY"
    fi
}


bootstrap_runtime_state() {
    local key="$ENV/sys-monitor-runtime/tf-state"
    bootstrap_state \
        "RUNTIME" \
        "$RUNTIME_DIR" \
        "$key"
}


apply_state() {
    bootstrap_bucket
    bootstrap_active_state
    bootstrap_runtime_state
}

plan_state() {
    local name="$1"
    local dir="$2"
    local key="$3"

    line
    echo "PLAN: $name STATE"
    line

    echo "Bucket : $STATE_BUCKET"
    echo "Key    : $key"
    echo "Profile: $STATE_PROFILE"
    echo

    terraform_init "$dir"
    terraform_validate "$dir"

    terraform -chdir="$dir" plan \
        -var="bucket=$STATE_BUCKET" \
        -var="env=$ENV" \
        -var="region=$REGION"
}

plan_state_bootstrap() {
    line
    echo "STATE BOOTSTRAP PLAN"
    line

    terraform_init "$BUCKET_DIR"
    terraform_validate "$BUCKET_DIR"

    terraform -chdir="$BUCKET_DIR" plan \
        -var="account_id=$STATE_ACCOUNT_ID" \
        -var="region=$REGION"

    if [[ "$CLUSTER_MODE" == "local" ]]; then
        plan_state \
            "LOCAL" \
            "$LOCAL_DIR" \
            "$ENV/sys-monitor-local/tf-state"
    else
        plan_state \
            "CROSS" \
            "$CROSS_DIR" \
            "$ENV/sys-monitor-cross/tf-state"
    fi

    plan_state \
        "RUNTIME" \
        "$RUNTIME_DIR" \
        "$ENV/sys-monitor-runtime/tf-state"
}

destroy_state() {
    echo "⚠️  This will destroy the sys_monitor state bootstrap."
    echo
    echo "Account : $STATE_ACCOUNT_ID"
    echo "Profile : $STATE_PROFILE"
    echo "Bucket  : $STATE_BUCKET"
    echo "Mode    : $CLUSTER_MODE"
    echo

    if [[ "$AUTO" != "true" ]]; then
      read -rp "Type 'yes' to continue: " CONFIRM
      if [[ "$CONFIRM" != "yes" ]]; then
          echo "❌ Destroy cancelled."
          exit 1
      fi
    fi

    bootstrap_state_destroy() {
        local name="$1"
        local dir="$2"
        local key="$3"

        terraform_init "$dir"

        if ! terraform_has_state "$dir"; then
            echo "ℹ️  $name state has no managed resources. Skipping."
            return 0
        fi

        line
        echo "DESTROY: $name STATE"
        line

        echo "Bucket : $STATE_BUCKET"
        echo "Key    : $key"
        echo "Profile: $STATE_PROFILE"
        echo

        terraform_validate "$dir"

        terraform -chdir="$dir" plan -destroy \
            -var="bucket=$STATE_BUCKET" \
            -var="env=$ENV" \
            -var="region=$REGION"

        terraform -chdir="$dir" destroy \
            --auto-approve \
            -var="bucket=$STATE_BUCKET" \
            -var="env=$ENV" \
            -var="region=$REGION"

        echo "✅ $name state destroyed: $key"
    }


    if [[ "$CLUSTER_MODE" == "local" ]]; then
        bootstrap_state_destroy \
            "RUNTIME" \
            "$RUNTIME_DIR" \
            "$ENV/sys-monitor-runtime/tf-state"

        bootstrap_state_destroy \
            "LOCAL" \
            "$LOCAL_DIR" \
            "$ACTIVE_STATE_KEY"
    else
        bootstrap_state_destroy \
            "RUNTIME" \
            "$RUNTIME_DIR" \
            "$ENV/sys-monitor-runtime/tf-state"

        bootstrap_state_destroy \
            "CROSS" \
            "$CROSS_DIR" \
            "$ACTIVE_STATE_KEY"
    fi


    line
    echo "DESTROY: STATE BUCKET"
    line

    terraform_init "$BUCKET_DIR"
    terraform_validate "$BUCKET_DIR"

    terraform -chdir="$BUCKET_DIR" plan -destroy \
        -var="account_id=$STATE_ACCOUNT_ID" \
        -var="region=$REGION"

    terraform -chdir="$BUCKET_DIR" destroy \
        --auto-approve \
        -var="account_id=$STATE_ACCOUNT_ID" \
        -var="region=$REGION"

    echo "✅ State bucket destroyed: $STATE_BUCKET"
}


validate_config
derive_config
show_config

check_directories \
    "$BUCKET_DIR" \
    "$CROSS_DIR" \
    "$LOCAL_DIR" \
    "$RUNTIME_DIR"

check_aws


case "$ACTION" in
    apply)
        apply_state
        line
        echo "✅ STATE BOOTSTRAP APPLY COMPLETE"
        ;;
    plan)
        plan_state_bootstrap
        line
        echo "✅ STATE BOOTSTRAP PLAN COMPLETE"
        ;;
    destroy)
        destroy_state
        ;;
    *)
        echo "❌ Unknown action: $ACTION"
        echo
        echo "Usage:"
        echo "  ./init_tf.sh apply"
        echo "  ./init_tf.sh plan"
        echo "  ./init_tf.sh destroy"
        exit 1
        ;;
esac
