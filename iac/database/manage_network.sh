#!/usr/bin/env bash

manage_network() {
    local mode="$1"

    if [[ "$mode" != "local" && "$mode" != "cross" ]]; then
        echo "❌ Invalid database mode: $mode"
        echo "Usage: $0 {local|cross}"
        exit 1
    fi

    local active_network
    local active_vars
    local inactive_network
    local inactive_vars

    if [[ "$mode" == "cross" ]]; then
        active_network="network_cross.tf"
        active_vars="cross.auto.tfvars"
        inactive_network="network_local.tf"
        inactive_vars="local.auto.tfvars"
    else
        active_network="network_local.tf"
        active_vars="local.auto.tfvars"
        inactive_network="network_cross.tf"
        inactive_vars="cross.auto.tfvars"
    fi

    local active_network_path="$DATABASE_DIR/$active_network"
    local active_vars_path="$DATABASE_DIR/$active_vars"

    local inactive_network_path="$DATABASE_DIR/$inactive_network"
    local inactive_vars_path="$DATABASE_DIR/$inactive_vars"

    local source_network_path="$STORE_DIR/$active_network"
    local source_vars_path="$STORE_DIR/$active_vars"

    # Remove inactive configuration.
    if [[ -f "$inactive_network_path" ]]; then
        rm -f "$inactive_network_path"
        echo "✓ Removed inactive: $inactive_network"
    fi

    if [[ -f "$inactive_vars_path" ]]; then
        rm -f "$inactive_vars_path"
        echo "✓ Removed inactive: $inactive_vars"
    fi

    # The network configuration is required.
    if [[ ! -f "$active_network_path" ]]; then
        if [[ ! -f "$source_network_path" ]]; then
            echo "❌ Required network configuration not found:"
            echo "   $source_network_path"
            exit 1
        fi

        cp "$source_network_path" "$active_network_path"
        echo "✓ Activated: $active_network"
    else
        echo "✓ Already active: $active_network"
    fi

    # Variables are optional.
    if [[ -f "$active_vars_path" ]]; then
        echo "✓ Already active: $active_vars"
    elif [[ -f "$source_vars_path" ]]; then
        cp "$source_vars_path" "$active_vars_path"
        echo "✓ Activated: $active_vars"
    else
        echo "ℹ No $active_vars found — continuing without it"
    fi
}
