#!/usr/bin/env bash

set -euo pipefail

ACTION="${1:-plan}"
RUN="${RUN:-laptop}"
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

DATABASE_DIR="$ROOT/iac/database"
ASSUME_DIR="$DATABASE_DIR/assume"
ASSUME_BOOT="$DATABASE_DIR/assume/boot"

SETUPS_ENV="$DATABASE_DIR/setups.env"
HELPERS="$DATABASE_DIR/helpers.sh"
MANAGE_NETWORK="$DATABASE_DIR/manage_network.sh"
STORE_DIR="$DATABASE_DIR/store"


if [[ "$ACTION" == "encrypt" ]]; then
    if [[ ! -f "$HELPERS" ]]; then
        echo "❌ Required file not found: $HELPERS"
        exit 1
    fi
    source "$HELPERS"
    encrypt_setup_env
    exit 0
fi

for file in "$HELPERS" "$MANAGE_NETWORK"; do
    if [[ ! -f "$file" ]]; then
        echo "❌ Required file not found: $file"
        exit 1
    fi
done

source "$HELPERS"
source "$MANAGE_NETWORK"

decrypt_setup_env
trap 'rm -f "$SETUPS_ENV"' EXIT
source "$SETUPS_ENV"

validate_config() {
    : "${ENV:?❌ ENV is required}"
    : "${DATABASE_MODE:?❌ DATABASE_MODE is required}"
    : "${KUBAPP_ACCOUNT_ID:?❌ KUBAPP_ACCOUNT_ID is required}"
    : "${REGION:?❌ REGION is required}"
    : "${GITHUB_ROLE:?❌ GITHUB_ROLE is required}"

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

    if [[ "$RUN" == "laptop" ]]; then
        export AWS_PROFILE="$STATE_PROFILE"
    fi
}


show_config() {
    line
    echo "KUBAPP DATABASE"
    line
    echo "ACTION       : $ACTION"
    echo "DATABASE MODE: $DATABASE_MODE"
    echo "ACCOUNT      : $STATE_ACCOUNT_ID"
    echo "PROFILE      : $STATE_PROFILE"
    echo "REGION       : $REGION"
    echo "STATE BUCKET : $STATE_BUCKET"
    echo "STATE KEY    : $STATE_KEY"
    echo "DATABASE DIR : $DATABASE_DIR"
    line
}

prepare_secrets() {
    source "$DATABASE_DIR/secrets.sh"
}

show_init_msg() {
    line
    echo "TERRAFORM INIT: DATABASE"
    line
}

run_init() {
    if [[ "$RUN" == "laptop" ]]; then
      terraform -chdir="$DATABASE_DIR" init -reconfigure \
        -backend-config="bucket=$STATE_BUCKET" \
        -backend-config="key=$STATE_KEY" \
        -backend-config="region=$REGION" \
        -backend-config="profile=$STATE_PROFILE"
    else
        terraform -chdir="$DATABASE_DIR" init -reconfigure \
            -backend-config="bucket=$STATE_BUCKET" \
            -backend-config="key=$STATE_KEY" \
            -backend-config="region=$REGION"
    fi
}

init_assume() {
    local ASSUME_KEY
    ASSUME_KEY="$(terraform -chdir="$ASSUME_BOOT" output -raw state_key 2>/dev/null || true)"
    [[ -z "$ASSUME_KEY" ]] && echo "Assume key Retrieval failed. check ASSUME BOOT" && exit 1
    terraform -chdir="$ASSUME_DIR" init -reconfigure \
        -backend-config="bucket=$STATE_BUCKET" \
        -backend-config="key=$ASSUME_KEY" \
        -backend-config="region=$REGION" \
        -backend-config="profile=$STATE_PROFILE"
}

prepare_assume_role() {
    if ! validate_assume; then
      return
    fi
    echo "============================================="
    echo "Preparing Assume Role Creations..."
    echo "============================================="
    init_assume
    terraform_validate "$ASSUME_DIR"
    terraform -chdir="$ASSUME_DIR" apply \
        -var="profile=$STATE_PROFILE" \
        -var="github_role=$GITHUB_ROLE" \
        -var="db_account_id=$DATABASE_ACCOUNT_ID" \
        -var="kubapp_account_id=$KUBAPP_ACCOUNT_ID" \
        --auto-approve
}

destroy_assume_role() {
    if ! validate_assume; then
      return
    fi
    echo "Destroying Assume Role Creations..."
    init_assume
    terraform_validate "$ASSUME_DIR"
    terraform -chdir="$ASSUME_DIR" destroy \
        -var="profile=$STATE_PROFILE" \
        -var="github_role=$GITHUB_ROLE" \
        -var="db_account_id=$DATABASE_ACCOUNT_ID" \
        -var="kubapp_account_id=$KUBAPP_ACCOUNT_ID" \
        --auto-approve
}

run_plan() {
    manage_network "$DATABASE_MODE"

    show_init_msg
    run_init
    prepare_secrets
    terraform_validate "$DATABASE_DIR"

    TF_VAR_state_bucket="$STATE_BUCKET" \
    TF_VAR_state_key="$STATE_KEY" \
    terraform -chdir="$DATABASE_DIR" plan
}


run_apply() {
    manage_network "$DATABASE_MODE"
    show_init_msg
    run_init

    prepare_secrets
    terraform_validate "$DATABASE_DIR"

    TF_VAR_state_bucket="$STATE_BUCKET" \
    TF_VAR_state_key="$STATE_KEY" \
    terraform -chdir="$DATABASE_DIR" plan

    TF_VAR_state_bucket="$STATE_BUCKET" \
    TF_VAR_state_key="$STATE_KEY" \
    terraform -chdir="$DATABASE_DIR" apply --auto-approve
}


run_destroy() {
    if [[ "$AUTO" != "true" ]]; then
        echo
        echo "⚠️  This will destroy the KUBAPP database Terraform resources."
        echo
        echo "Account : $STATE_ACCOUNT_ID"
        echo "Profile : $STATE_PROFILE"
        echo "Mode    : $DATABASE_MODE"
        echo

        read -rp "Type 'yes' to continue: " CONFIRM

        if [[ "$CONFIRM" != "yes" ]]; then
            echo "❌ Destroy cancelled."
            return 1
        fi
    fi

    manage_network "$DATABASE_MODE"

    run_init

    terraform_validate "$DATABASE_DIR"
    prepare_secrets

    TF_VAR_state_bucket="$STATE_BUCKET" \
    TF_VAR_state_key="$STATE_KEY" \
    terraform -chdir="$DATABASE_DIR" plan -destroy

    TF_VAR_state_bucket="$STATE_BUCKET" \
    TF_VAR_state_key="$STATE_KEY" \
    terraform -chdir="$DATABASE_DIR" destroy \
        --auto-approve
}


validate_config
derive_config
show_config

check_directories \
    "$DATABASE_DIR" \
    "$STORE_DIR"  \
    "$ASSUME_DIR"

check_aws

case "$ACTION" in

    init)
        run_init
        ;;

    plan)
        prepare_assume_role
        run_plan
        ;;

    apply)
        prepare_assume_role
        run_apply
        ;;

    destroy)
        run_destroy
        destroy_assume_role
        ;;

    *)
        echo "❌ Unknown action: $ACTION"
        echo
        echo "Usage:"
        echo "  ./runner.sh init"
        echo "  ./runner.sh plan"
        echo "  ./runner.sh apply"
        echo "  ./runner.sh destroy"
        echo "  ./runner.sh destroy -y"
        exit 1
        ;;

esac
