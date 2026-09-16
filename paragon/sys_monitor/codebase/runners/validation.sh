#!/bin/bash
set +euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/runtime.sh"
source "${CODEBASE_ROOT}/lib/json.sh"

MODULE_NAME="validation"
VALIDATION_FILE="$(evidence_file "validation")"

log_info "validation engine starting....."

require_binary "jq"
require_binary "helm"
require_binary "terraform"

# ============================================================
# STATE
# ============================================================

TOTAL_CHECKED=0
ISSUES=()

CRITICAL=0
WARNINGS=0
STATUS="pass"

DOCKER_FINDINGS=0
HELM_CHARTS_CHECKED=0

# ============================================================
# HELPERS
# ============================================================

resolve() {
    [[ "$1" == /* ]] && echo "$1" || echo "${PROJECT_ROOT}/$1"
}

is_docker_file() {
    [[ "$1" == docker/* ]]
}

is_helm_template_file() {
    [[ "$1" == gitops/charts/*/templates/* ]]
}

get_helm_chart_dir() {
    echo "$1" | awk -F"/templates/" '{print $1}'
}

# ============================================================
# POLICY ENGINE (NEW CORE)
# ============================================================

is_whitelisted_file() {
    case "$1" in
        *.md|*.txt|*.tfvars|*.hcl|LICENSE|.gitignore|*Dockerfile|.trivyignore|.dockerignore|.html|.css)
            return 0 ;;
    esac
    return 1
}

is_config_file() {
    case "$1" in
        *.conf|*.j2|*.j2.conf|*.ini|*.env|*.enc)
            return 0 ;;
    esac
    return 1
}

is_code_file() {
    [[ "$1" =~ \.(sh|py|js|ts|tf|yaml|yml|json)$ ]]
}

# ============================================================
# STRICT TYPE DETECTION
# ============================================================

detect_type() {
    local file="$1"
    local base ext

    base="$(basename "$file")"
    ext="${file##*.}"

    case "$base" in
        Dockerfile) echo "dockerfile"; return ;;
    esac

    case "$ext" in
        sh) echo "sh" ;;
        py) echo "py" ;;
        js) echo "js" ;;
        ts) echo "ts" ;;
        tf) echo "tf" ;;
        yaml|yml) echo "yaml" ;;
        json) echo "json" ;;
        txt) echo "txt" ;;
        *) echo "unknown:$ext" ;;
    esac
}

# ============================================================
# ISSUE ENGINE
# ============================================================

add_issue() {
    local severity="$1"
    local type="$2"
    local file="$3"
    local message="$4"
    local extra="${5:-}"

    ISSUES+=(
        "$(jq -n \
            --arg severity "$severity" \
            --arg type "$type" \
            --arg file "$file" \
            --arg message "$message" \
            --arg extra "$extra" \
            '{severity:$severity,type:$type,file:$file,message:$message,extra:$extra}'
        )"
    )

    if [[ "$severity" == "critical" ]]; then
        STATUS="fail"
        CRITICAL=$((CRITICAL + 1))
    else
        WARNINGS=$((WARNINGS + 1))
    fi

    if is_docker_file "$file"; then
        DOCKER_FINDINGS=$((DOCKER_FINDINGS + 1))
    fi
}

# ============================================================
# CORE VALIDATION
# ============================================================

validate_file() {
    local file="$1"
    local path type

    path="$(resolve "$file")"
    TOTAL_CHECKED=$((TOTAL_CHECKED + 1))

    # ----------------------------
    # missing file
    # ----------------------------
    if [[ ! -f "$path" ]]; then
        add_issue "critical" "missing_file" "$file" "file not found"
        return
    fi

    # ----------------------------
    # HELM
    # ----------------------------
    if is_helm_template_file "$file"; then
        chart_dir="$(get_helm_chart_dir "$path")"

        helm template test "$chart_dir" >/dev/null 2>&1 || \
            add_issue "warning" "helm_template" "$file" "helm render warning"

        HELM_CHARTS_CHECKED=$((HELM_CHARTS_CHECKED + 1))
        return
    fi

    # ----------------------------
    # CONFIG FILES (allowed but NOT silently ignored)
    # ----------------------------
    if is_config_file "$file"; then
        return
    fi

    # ========================================================
    # RULE 1: WHITELIST CHECK (IMPORTANT FIX)
    # ========================================================

    if ! is_whitelisted_file "$file" && ! is_code_file "$file"; then
        add_issue "warning" "unknown_file_type" "$file" \
            "file not in whitelist or code registry"
        return
    fi

    type="$(detect_type "$file")"

    # ========================================================
    # RULE 2: UNKNOWN TYPES (STRICT)
    # ========================================================

    if [[ "$type" == unknown:* ]]; then
        add_issue "warning" "unknown_file_type" "$file" \
            "File type not validatable in line with KubApp policy" "${type#unknown:}"
        return
    fi

    # ========================================================
    # VALIDATION
    # ========================================================

    case "$type" in

        sh)
            bash -n "$path" >/dev/null 2>&1 || \
                add_issue "warning" "bash_syntax" "$file" "bash syntax error"
            ;;

        py)
            python3 -m py_compile "$path" >/dev/null 2>&1 || \
                add_issue "warning" "python_syntax" "$file" "python syntax error"
            ;;

        js|ts)
            node --check "$path" >/dev/null 2>&1 || \
                add_issue "warning" "js_syntax" "$file" "js/ts syntax error"
            ;;

        yaml)
            python3 -c "import yaml; yaml.safe_load(open('$path'))" >/dev/null 2>&1 || \
                add_issue "warning" "yaml_syntax" "$file" "invalid yaml"
            ;;

        json)
            jq empty "$path" >/dev/null 2>&1 || \
                add_issue "warning" "json_syntax" "$file" "invalid json"
            ;;

        tf)
            terraform fmt -check "$(dirname "$path")" >/dev/null 2>&1 || \
                add_issue "warning" "terraform_format" "$file" "terraform format issue"
            ;;

        dockerfile)
            grep -q "^FROM" "$path" || \
                add_issue "warning" "dockerfile_syntax" "$file" "missing FROM instruction"
            ;;

        txt|md|tfvars|hcl)
            # safe but still counted in whitelist system
            ;;
    esac
}

# ============================================================
# MAIN LOOP
# ============================================================

log_info "loading inventory"
mapfile -t ALL_FILES < <(jq -r '.files.all_files[]?' "$INVENTORY_FILE")

log_info "processing files"

for f in "${ALL_FILES[@]}"; do
    [[ -z "$f" ]] && continue
    validate_file "$f"
done

# ============================================================
# OUTPUT
# ============================================================

cat > "$VALIDATION_FILE" <<EOF
{
  "module": "$MODULE_NAME",
  "script": "$SCRIPT_NAME",
  "timestamp": "$TIMESTAMP",
  "status": "$STATUS",

  "summary": {
    "total_checked": $TOTAL_CHECKED,
    "critical": $CRITICAL,
    "warnings": $WARNINGS,
    "issues_found": ${#ISSUES[@]},
    "app_section_findings": $DOCKER_FINDINGS,
    "helm_charts_checked": $HELM_CHARTS_CHECKED
  },

  "errors": $CRITICAL,
  "warnings": $WARNINGS,

  "findings": $(printf "%s\n" "${ISSUES[@]}" | jq -s .)
}
EOF

log_info "validation complete"
log_info "status=$STATUS"
log_info "output=$VALIDATION_FILE"

exit 0
