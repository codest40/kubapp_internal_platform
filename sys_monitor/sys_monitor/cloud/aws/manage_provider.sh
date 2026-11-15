manage_provider() {
    local arg="$1"

    if [[ "$arg" != "cross" && "$arg" != "local" ]]; then
        echo "❌ Invalid mode: $arg"
        exit 1
    fi

    local active_file
    local inactive_file

    if [[ "$arg" == "cross" ]]; then
        active_file="config_cross.tf"
        inactive_file="config_local.tf"
    else
        active_file="config_local.tf"
        inactive_file="config_cross.tf"
    fi

    # Remove the inactive configuration from main/
    if [[ -f "$MAIN_DIR/$inactive_file" ]]; then
        rm "$MAIN_DIR/$inactive_file"
    fi

    # Requested configuration is already active
    if [[ -f "$MAIN_DIR/$active_file" ]]; then
        echo "✓ $active_file already active"
        return 0
    fi

    # Activate requested configuration from store/
    if [[ -f "$STORE_DIR/$active_file" ]]; then
        cp "$STORE_DIR/$active_file" "$MAIN_DIR/"
        echo "✓ Activated $active_file"
        return 0
    fi

    echo "❌ $active_file not found in $MAIN_DIR or $STORE_DIR"
    exit 1
}
