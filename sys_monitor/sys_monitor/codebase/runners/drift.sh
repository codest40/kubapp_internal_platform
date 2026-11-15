#!/bin/bash

# ============================================================
# KUBAPP — DRIFT ENGINE
# SOURCE OF TRUTH: inventory.json ONLY
# NO FILESYSTEM DISCOVERY ALLOWED
# ============================================================

set -uo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/runtime.sh"
source "${CODEBASE_ROOT}/lib/json.sh"

MODULE_NAME="drift"
DRIFT_FILE="$(evidence_file "drift")"
OUTPUT_FILE="${DRIFT_FILE}"

log_info "drift (schema-locked) starting"

require_binary "jq"

# ============================================================
# LOAD INVENTORY (ONLY SOURCE OF TRUTH)
# ============================================================

if [[ ! -f "${INVENTORY_FILE}" ]]; then
    log_error "inventory missing"
    exit 1
fi

INVENTORY="$(cat "${INVENTORY_FILE}")"

if ! echo "$INVENTORY" | jq empty >/dev/null 2>&1; then
    log_error "inventory invalid json"
    exit 1
fi

# ============================================================
# STATE
# ============================================================

TOTAL_CHECKED=0
FINDINGS=()

TOTAL_CHECKED() {
  TOTAL_CHECKED=$((TOTAL_CHECKED + 1))
}

add_finding() {
    local severity="$1"
    local type="$2"
    local file="$3"
    local message="$4"

    FINDINGS+=(
        "$(jq -n \
            --arg severity "$severity" \
            --arg type "$type" \
            --arg file "$file" \
            --arg message "$message" \
            '{severity:$severity,type:$type,file:$file,message:$message}'
        )"
    )
}

# ============================================================
# CANONICAL FILESET (FROM DISCOVERY ONLY)
# ============================================================

mapfile -t INVENTORY_FILES < <(
    echo "$INVENTORY" | jq -r '
        .files.all_files[]?
    ' | sort -u
)

# ============================================================
# FILESYSTEM EXISTENCE CHECK (NO DISCOVERY LOGIC)
# ============================================================

log_info "validating inventory against filesystem"

for file in "${INVENTORY_FILES[@]}"; do
    TOTAL_CHECKED

    path="$(resolve_path "$file")"

    if [[ ! -e "$path" ]]; then
        add_finding \
            "critical" \
            "missing_file" \
            "$file" \
            "declared in inventory but missing on disk"
    fi
done

# ============================================================
# ORPHAN CHECK (ONLY AGAINST INVENTORY FILES LIST)
# ============================================================

log_info "checking orphan files strictly via inventory.all_files"

mapfile -t FS_FILES < <(
    printf "%s\n" "${INVENTORY_FILES[@]}"
)

INVENTORY_SET="$(printf "%s\n" "${INVENTORY_FILES[@]}" | sort -u)"

for file in "${FS_FILES[@]}"; do
    TOTAL_CHECKED

    if ! grep -Fxq "$file" <<< "$INVENTORY_SET"; then
        add_finding \
            "warning" \
            "orphan_file" \
            "$file" \
            "filesystem file not in discovery inventory"
    fi
done

# ============================================================
# TF VALIDATION (STRUCTURAL ONLY, NOT FILE-LEVEL)
# ============================================================

TF_ROOTS=$(echo "$INVENTORY" | jq -r '.terraform.roots[]?')
TF_MODULES=$(echo "$INVENTORY" | jq -r '.terraform.modules[]?')

for dir in $TF_ROOTS; do
    TOTAL_CHECKED
    [[ ! -d "$(resolve_path "$dir")" ]] && \
        add_finding "critical" "missing_tf_root" "$dir" "missing terraform root"
done

for dir in $TF_MODULES; do
    TOTAL_CHECKED
    [[ ! -d "$(resolve_path "$dir")" ]] && \
        add_finding "critical" "missing_tf_module" "$dir" "missing terraform module"
done

# ============================================================
# OUTPUT
# ============================================================

log_info "writing drift output"

FINDINGS_JSON="$(printf "%s\n" "${FINDINGS[@]}" | jq -s .)"

cat > "$OUTPUT_FILE" <<EOF
{
  "module": "$MODULE_NAME",
  "script": "$SCRIPT_NAME",
  "timestamp": "$TIMESTAMP",
  "status": "$STATUS",

  "summary": {
    "total_checked": $TOTAL_CHECKED,
    "findings": ${#FINDINGS[@]},
    "errors": ${#ERRORS[@]},
    "warnings": ${#WARNINGS[@]}
  },

  "errors": $(json_errors),
  "warnings": $(json_warnings),

  "findings": $FINDINGS_JSON
}
EOF

log_info "drift v3 completed"
exit 0
