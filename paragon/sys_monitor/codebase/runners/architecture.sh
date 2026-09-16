#!/bin/bash
set -uo pipefail

# ============================================================
# ARCHITECTURE ENGINE
# ROLE: SYSTEM DESIGN HEALTH ONLY
# ============================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/runtime.sh"
source "${CODEBASE_ROOT}/lib/json.sh"

MODULE_NAME="architecture"
OUTPUT_FILE="$(evidence_file "architecture")"

log_info "architecture engine starting"

require_binary "jq"

# ============================================================
# STATE (runtime-aware)
# ============================================================

TOTAL_CHECKED=0
ISSUES=()

CRITICAL=0
WARNINGS=0
ISSUES_FOUND=0

# ============================================================
# SAFE INVENTORY LOAD
# ============================================================

log_info "loading inventory from ${INVENTORY_FILE}"

INVENTORY="{}"
if [[ -f "$INVENTORY_FILE" ]]; then
    INVENTORY="$(cat "$INVENTORY_FILE" || echo '{}')"
else
    log_warn "inventory missing"
fi

# ============================================================
# HELPERS
# ============================================================

inc_check() {
    TOTAL_CHECKED=$((TOTAL_CHECKED + 1))
}

jq_array() {
    jq -r "$1" <<< "$INVENTORY" 2>/dev/null || true
}

# ============================================================
# LOAD LAYERS (FROM INVENTORY ONLY)
# ============================================================

mapfile -t SCRIPTS < <(jq_array '.shell_scripts[]?')
mapfile -t TF_ROOTS < <(jq_array '.terraform.roots[]?')
mapfile -t WORKFLOWS < <(jq_array '.workflows[]?')

# ============================================================
# ISSUE ENGINE (JSON-COMPLIANT)
# ============================================================

add_issue() {
    local severity="$1"
    local type="$2"
    local area="$3"
    local message="$4"

    ISSUES+=(
        "$(jq -n \
            --arg severity "$severity" \
            --arg type "$type" \
            --arg area "$area" \
            --arg message "$message" \
            '{
                severity: $severity,
                type: $type,
                area: $area,
                message: $message
            }'
        )"
    )

    ISSUES_FOUND=$((ISSUES_FOUND + 1))

    if [[ "$severity" == "critical" ]]; then
        CRITICAL=$((CRITICAL + 1))
    else
        WARNINGS=$((WARNINGS + 1))
    fi
}

# ============================================================
# RULE 1 — SAMPLE ISOLATION
# ============================================================

log_info "checking sample isolation"

for f in "${SCRIPTS[@]:-}"; do
    [[ -z "$f" ]] && continue
    inc_check

    [[ "$f" == sample/* ]] && \
        add_issue "warning" "isolation" "sample" "sample script leakage into automation layer"
done

# ============================================================
# RULE 2 — SYS_MONITOR BOUNDARY
# ============================================================

log_info "checking sys_monitor boundaries"

for f in "${SCRIPTS[@]:-}"; do
    [[ -z "$f" ]] && continue
    inc_check

    [[ "$f" == sys_monitor/cloud/* ]] && \
        add_issue "warning" "boundary" "sys_monitor" "cloud logic inside monitoring layer"
done

# ============================================================
# RULE 3 — DUPLICATION
# ============================================================

log_info "checking duplication rules"

find_count=0
validate_count=0

for f in "${SCRIPTS[@]:-}"; do
    [[ -z "$f" ]] && continue
    inc_check

    case "$f" in
        *find*.sh) ((find_count++)) ;;
        *validate*.sh) ((validate_count++)) ;;
    esac
done

(( find_count > 1 )) && \
    add_issue "warning" "duplication" "scripts" "multiple find tools detected"

(( validate_count > 1 )) && \
    add_issue "warning" "duplication" "scripts" "multiple validate tools detected"

# ============================================================
# RULE 4 — INFRA COUPLING
# ============================================================

log_info "checking infra coupling"

for f in "${SCRIPTS[@]:-}"; do
    [[ -z "$f" ]] && continue
    inc_check

    [[ "$f" == *iac* ]] && \
        add_issue "warning" "coupling" "scripts" "iac coupling detected"
done

# ============================================================
# RULE 5 — WORKFLOW BALANCE
# ============================================================

log_info "checking workflow balance"

SCRIPT_COUNT=${#SCRIPTS[@]}
WORKFLOW_COUNT=${#WORKFLOWS[@]}

if (( WORKFLOW_COUNT > 0 && SCRIPT_COUNT > WORKFLOW_COUNT * 10 )); then
    add_issue "warning" "imbalance" "automation" "script layer dominates workflows"
fi

# ============================================================
# OUTPUT
# ============================================================

ARCH_SCORE=$((100 - ISSUES_FOUND * 3))
(( ARCH_SCORE < 0 )) && ARCH_SCORE=0

cat > "$OUTPUT_FILE" <<EOF
{
  "module": "$MODULE_NAME",
  "script": "$SCRIPT_NAME",
  "status": "completed",
  "timestamp": "$TIMESTAMP",

  "summary": {
    "total_checked": $TOTAL_CHECKED,
    "issues_found": $ISSUES_FOUND,
    "critical": $CRITICAL,
    "warnings": $WARNINGS,
    "architecture_score": $ARCH_SCORE
  },

  "findings": $(printf "%s\n" "${ISSUES[@]}" | jq -s '.')
}
EOF

log_info "architecture evaluation completed"
log_info "issues=$ISSUES_FOUND"
log_info "output=$OUTPUT_FILE"

exit 0
