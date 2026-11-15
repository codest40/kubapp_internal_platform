#!/bin/bash

# ============================================================
# KUBAPP — CODEBASE RUNTIME LIBRARY
# ============================================================
set +euo pipefail

STATUS="pass"
ERRORS=()
WARNINGS=()
TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

# ============================================================
# PATH RESOLUTION
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
SCRIPT_NAME="$(basename "${BASH_SOURCE[-1]}")"
CODEBASE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if GIT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    PROJECT_ROOT="${GIT_ROOT}"
else
    PROJECT_ROOT="$(cd "${CODEBASE_ROOT}/../.." && pwd)"
fi

EVIDENCE_DIR="${CODEBASE_ROOT}/evidence"
INVENTORY_FILE="${EVIDENCE_DIR}/inventory.json"

mkdir -p "${EVIDENCE_DIR}"

# ============================================================
# LOGGING
# ============================================================

log_info() {
    echo "[INFO] $1" >&2
}

log_warn() {
    echo "[WARN] $1" >&2
}

log_error() {
    echo "[ERROR] $1" >&2
}

# ============================================================
# ERROR HANDLING
# ============================================================

handle_error() {
    local line="$1"
    local exit_code="${2:-1}"

    STATUS="fail"

    ERRORS+=(
        "command failed at line ${line} with exit code ${exit_code}"
    )
}

trap 'handle_error $LINENO $?' ERR

# ============================================================
# SAFE EXECUTION
# ============================================================

safe_run() {
    local description="$1"

    shift

    if ! "$@"; then
        STATUS="fail"

        ERRORS+=("${description} failed")

        return 1
    fi
}

# ============================================================
# VALIDATION HELPERS
# ============================================================
evidence_file() {
    local name="$1"

    if [[ -z "$name" ]]; then
        STATUS="fail"
        ERRORS+=("evidence file name missing")
        return 1
    fi

    echo "${EVIDENCE_DIR}/${name}.json"
}

resolve_path() {
    local p="$1"

    if [[ "$p" == /* ]]; then
        echo "$p"
    else
        echo "${PROJECT_ROOT}/${p}"
    fi
}

relative_path() {
    local p="$1"

    if [[ "$p" == "${PROJECT_ROOT}/"* ]]; then
        echo "${p#"${PROJECT_ROOT}/"}"
    else
        echo "$p"
    fi
}

require_binary() {
    local binary="$1"

    if ! command -v "${binary}" >/dev/null 2>&1; then
        STATUS="fail"

        ERRORS+=("required binary missing: ${binary}")

        return 1
    fi
}

require_directory() {
    local dir="$1"

    if [[ ! -d "${dir}" ]]; then
        STATUS="fail"

        ERRORS+=("required directory missing: ${dir}")

        return 1
    fi
}

require_file() {
    local file="$1"

    if [[ ! -f "${file}" ]]; then
        STATUS="fail"

        ERRORS+=("required file missing: ${file}")

        return 1
    fi
}

GLOBAL_EXCLUDES=(
    "*/.git/*"
    "*/.terraform/*"
    "*/.backup/*"
    "*/__pycache__/*"
    "sample/*"
    "*.bak"
    "*.tmp"
    "*.swp"

    "*.terraform.*"
    "*.terraform.lock.hcl*"
    "*/terraform.tfstate"
    "*/terraform.tfstate.*"
)

build_find_excludes() {
    EXCLUDE_ARGS=()

    for pattern in "${GLOBAL_EXCLUDES[@]}"; do
        EXCLUDE_ARGS+=( ! -path "${pattern}" )
    done
}
