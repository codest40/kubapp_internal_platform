#!/usr/bin/env bash

set -euo pipefail

ACTION="${1:-plan}"
AUTO="${2:-false}"

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[[ -z "$ROOT" ]] && echo "❌ Unable to determine project root." && exit 1

DATABASE_DIR="$ROOT/iac/database"
BOOT_DIR="$DATABASE_DIR/boot"
ASSUME_DIR="$DATABASE_DIR/assume/boot"

SETUP_ENV="$DATABASE_DIR/setup.env"
HELPERS="$DATABASE_DIR/helpers.sh"

if [[ ! -f "$SETUP_ENV" ]]; then
    echo "❌ setup.env not found: $SETUP_ENV"
    exit 1
fi

if [[ ! -f "$HELPERS" ]]; then
    echo "❌ helpers.sh not found: $HELPERS"
    exit 1
fi

for i in "-y" "y" "-yes"; do
  if [[ "${AUTO,,}" == "$i" ]]; then
    AUTO="true"
  fi
done

source "$SETUP_ENV"
source "$HELPERS"


validate_config() {
    : "${ENV:?❌ ENV is required}"
    : "${DATABASE_MODE:?❌ DATABASE_MODE is required}"
    : "${KUBAPP_ACCOUNT_ID:?❌ KUBAPP_ACCOUNT_ID is required}"
    : "${REGION:?❌ REGION is required}"

    if [[ "$DATABASE_MODE" != "local" && "$DATABASE_MODE" != "cross" ]]; then
        echo "❌ Invalid DATABASE_MODE: $DATABASE_MODE"
        echo "   Expected: local or cross"
        exit 1
    fi

    if [[ "$DATABASE_MODE" == "local" ]]; then
        : "${PROFILE_LOCAL:?❌ PROFILE_LOCAL is required}"
    else
        : "${DATABASE_ACCOUNT_ID:?❌ DATABASE_ACCOUNT_ID is required}"
        : "${PROFILE_CROSS:?❌ PROFILE_CROSS is required}"
    fi
}


derive_config() {
    if [[ "$DATABASE_MODE" == "local" ]]; then
        STATE_ACCOUNT_ID="$KUBAPP_ACCOUNT_ID"
        STATE_PROFILE="$PROFILE_LOCAL"
    else
        STATE_ACCOUNT_ID="$DATABASE_ACCOUNT_ID"
        STATE_PROFILE="$PROFILE_CROSS"
    fi

    STATE_BUCKET="kubapp-database-tf-state-${STATE_ACCOUNT_ID}"
    STATE_KEY="${ENV}/database/tf-state"
    set_aws_profile "$STATE_PROFILE"
}


show_config() {
    line
    echo "DATABASE STATE BOOTSTRAP"
    line
    echo "MODE         : $DATABASE_MODE"
    echo "ACTION       : $ACTION"
    echo "ACCOUNT      : $STATE_ACCOUNT_ID"
    echo "PROFILE      : $STATE_PROFILE"
    echo "REGION       : $REGION"
    echo "BUCKET       : $STATE_BUCKET"
    echo "STATE KEY    : $STATE_KEY"
    line
}


bootstrap_state() {
    line
    echo "BOOTSTRAP: DATABASE STATE"
    line

    echo "Bucket : $STATE_BUCKET"
    echo "Key    : $STATE_KEY"
    echo "Profile: $STATE_PROFILE"
    echo

    terraform_init "$BOOT_DIR"
    terraform_validate "$BOOT_DIR"

    terraform -chdir="$BOOT_DIR" plan \
        -var="account_id=$STATE_ACCOUNT_ID" \
        -var="region=$REGION" \
        -var="env=$ENV"

    if [[ "$ACTION" == "apply" ]]; then
        terraform -chdir="$BOOT_DIR" apply \
            --auto-approve \
            -var="account_id=$STATE_ACCOUNT_ID" \
            -var="region=$REGION" \
            -var="env=$ENV"

        echo
        echo "✅ Database state ready"
        echo "   Bucket : $STATE_BUCKET"
        echo "   Key    : $STATE_KEY"
    fi
}


destroy_state() {
    line
    echo "DESTROY: DATABASE STATE"
    line

    echo "Bucket : $STATE_BUCKET"
    echo "Key    : $STATE_KEY"
    echo "Profile: $STATE_PROFILE"
    echo

    if [[ "$AUTO" != "true" ]]; then
        read -rp "Type 'yes' to continue: " CONFIRM

        if [[ "$CONFIRM" != "yes" ]]; then
            echo "❌ Destroy cancelled."
            exit 1
        fi
    fi

    terraform_init "$BOOT_DIR"
    terraform_validate "$BOOT_DIR"

    terraform -chdir="$BOOT_DIR" plan -destroy \
        -var="account_id=$STATE_ACCOUNT_ID" \
        -var="region=$REGION" \
        -var="env=$ENV"

    terraform -chdir="$BOOT_DIR" destroy \
        --auto-approve \
        -var="account_id=$STATE_ACCOUNT_ID" \
        -var="region=$REGION" \
        -var="env=$ENV"

    echo
    echo "✅ Database state bootstrap destroyed"
}

run_assume() {
    if ! validate_assume; then
      return
    fi

    echo "=========================================="
    echo "ACTIVATING ASSUME $ASSUME_DIR"
    echo "=========================================="
    terraform_init "$ASSUME_DIR"

    terraform_validate "$ASSUME_DIR"
    if [[ "$ACTION" == "apply" ]]; then
        terraform -chdir="$ASSUME_DIR" apply \
            --auto-approve \
            -var="bucket_name=$STATE_BUCKET" \
            -var="account_id=$STATE_ACCOUNT_ID" \
            -var="region=$REGION" \
            -var="env=$ENV"
    else
        terraform -chdir="$ASSUME_DIR" destroy \
            --auto-approve \
            -var="bucket_name=$STATE_BUCKET" \
            -var="account_id=$STATE_ACCOUNT_ID" \
            -var="region=$REGION" \
            -var="env=$ENV"
    fi
}


validate_config
derive_config
show_config

check_directories "$BOOT_DIR"
check_aws

case "$ACTION" in
    plan)
        bootstrap_state
        line
        echo "✅ DATABASE STATE BOOTSTRAP PLAN COMPLETE"
        ;;

    apply)
        bootstrap_state
        run_assume
        line
        echo "✅ DATABASE STATE BOOTSTRAP APPLY COMPLETE"
        ;;

    destroy)
        run_assume
        destroy_state
        ;;

    *)
        echo "❌ Unknown action: $ACTION"
        echo
        echo "Usage:"
        echo "  ./init_tf.sh plan"
        echo "  ./init_tf.sh apply"
        echo "  ./init_tf.sh destroy"
        echo "  ./init_tf.sh destroy yes"
        exit 1
        ;;
esac
