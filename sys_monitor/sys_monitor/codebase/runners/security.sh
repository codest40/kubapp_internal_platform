#!/bin/bash

# ============================================================
# KUBAPP — CODEBASE SECURITY ENGINE
# ============================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/runtime.sh"
source "${CODEBASE_ROOT}/lib/json.sh"

MODULE_NAME="security"

SECURITY_FILE="$(evidence_file "security")"
OUTPUT_FILE="${SECURITY_FILE}"

log_info "security engine started"
build_find_excludes
# ============================================================
# VALIDATION
# ============================================================

require_binary "git"
require_binary "jq"
require_binary "grep"

# ============================================================
# STATE
# ============================================================

TOTAL_CHECKED=0
FINDINGS=()

# ============================================================
# LOAD INVENTORY
# ============================================================

log_info "loading inventory from ${INVENTORY_FILE}"

INVENTORY="{}"

if [[ -f "${INVENTORY_FILE}" ]]; then
    INVENTORY="$(cat "${INVENTORY_FILE}" 2>/dev/null)"

    if ! echo "${INVENTORY}" | jq empty >/dev/null 2>&1; then
        STATUS="fail"
        ERRORS+=("inventory json invalid")
        INVENTORY="{}"
    fi
else
    STATUS="fail"
    ERRORS+=("inventory file missing")
fi

# ============================================================
# FINDING HANDLER
# ============================================================

add_finding() {
    local severity="$1"
    local type="$2"
    local file="$3"
    local message="$4"
    local relative
    relative="$(relative_path "${file}")"

    FINDINGS+=(
        "$(jq -n \
            --arg severity "${severity}" \
            --arg type "${type}" \
            --arg file "${relative}" \
            --arg message "${message}" \
            '{
                severity: $severity,
                type: $type,
                file: $file,
                message: $message
            }'
        )"
    )

    if [[ "${severity}" == "critical" ]]; then
        STATUS="fail"
        ERRORS+=("${type}: ${file}")
    else
        WARNINGS+=("${type}: ${file}")
    fi
}

check_gitignore() {
  local arg=$1
  if  git check-ignore -q "$arg" 2>/dev/null; then
    return 0
  fi
  return 1
}

has_private_key() {
    local file="$1"

    perl -0777 -ne '
        exit 0 if /-----BEGIN (?:RSA |EC |OPENSSH |DSA |PGP )?PRIVATE KEY-----.*?-----END (?:RSA |EC |OPENSSH |DSA |PGP )?PRIVATE KEY-----/s;
        exit 1;
    ' "${file}" 2>/dev/null

    return $?
}

# ============================================================
# SAFE JSON EXTRACTOR
# ============================================================

extract_inventory() {
    local query="$1"

    echo "${INVENTORY}" \
        | jq -r "${query}[]? // empty" 2>/dev/null
}

# ============================================================
# LOAD SECURITY DATASETS
# ============================================================

mapfile -t REPO_SECRETS < <(
    extract_inventory '.repo_secrets'
)

mapfile -t WORKFLOWS < <(
    extract_inventory '.workflows'
)

mapfile -t SHELL_SCRIPTS < <(
    extract_inventory '.shell_scripts'
)

mapfile -t K8S_MANIFESTS < <(
    extract_inventory '.yaml.kubernetes_manifests'
)

# ============================================================
# 1. SECRET FILE EXISTENCE
# ============================================================

log_info "validating secret file existence"

for file in "${REPO_SECRETS[@]}"; do
    TOTAL_CHECKED=$((TOTAL_CHECKED + 1))

    path="$(resolve_path "${file}")"

    if [[ ! -f "${path}" ]]; then
        add_finding \
            "critical" \
            "missing_secret_file" \
            "${file}" \
            "security-sensitive file missing"
    fi
done

# ============================================================
# 2. ENCRYPTED TFVARS VALIDATION
# ============================================================

log_info "validating encrypted tfvars"

while IFS= read -r file; do
    TOTAL_CHECKED=$((TOTAL_CHECKED + 1))

    path="$(resolve_path "${file}")"

    if [[ "${file}" == *.tfvars ]]; then
      if ! check_gitignore ".tfvars"; then
        add_finding \
            "critical" \
            "plaintext_tfvars" \
            "${file}" \
            "plaintext tfvars file detected"
      fi
    fi

    if [[ "${file}" == *.tfvars.enc ]]; then
        if [[ ! -f "${path}" ]]; then
            add_finding \
                "critical" \
                "missing_encrypted_tfvars" \
                "${file}" \
                "encrypted tfvars missing"
        elif  check_gitignore ".tfvars.enc"; then
            add_finding \
                "critical" \
                "encrypted_tfvars_ignored" \
                "${file}" \
                "encrypted tfvar is being ignored"
        fi
    fi

done < <(
    find "${PROJECT_ROOT}" -type f "${EXCLUDE_ARGS[@]}" \
        \( -name "*.tfvars" -o -name "*.tfvars.enc" \)
)

# ============================================================
# 3. SECRET BACKUP FILE DETECTION
# ============================================================

log_info "detecting backup secret files"

for file in "${REPO_SECRETS[@]}"; do
    TOTAL_CHECKED=$((TOTAL_CHECKED + 1))

    if [[ "${file}" == *.bak ]]; then
      if ! check_gitignore ".bak"; then
        add_finding \
            "warning" \
            "backup_secret_file" \
            "${file}" \
            "backup secret file detected"
      fi
    fi
done

# ============================================================
# 4. PRIVATE KEY DETECTION
# ============================================================

log_info "detecting private key exposure"

while IFS= read -r file; do
    TOTAL_CHECKED=$((TOTAL_CHECKED + 1))

    if file "${file}" | grep -qi "binary"; then
        continue
    fi
    if has_private_key "${file}"; then
        relative="$(relative_path "${file}")"

        add_finding \
            "critical" \
            "private_key_exposed" \
            "${relative}" \
            "private key material detected"
    fi

done < <(
    find "${PROJECT_ROOT}" -type f "${EXCLUDE_ARGS[@]}"
)

# ============================================================
# 5. GITOPS SECRET PLACEMENT
# ============================================================

log_info "validating gitops secret placement"

for file in "${K8S_MANIFESTS[@]}"; do
    TOTAL_CHECKED=$((TOTAL_CHECKED + 1))
    #((TOTAL_CHECKED++))

    path="$(resolve_path "${file}")"

    if [[ ! -f "${path}" ]]; then
        continue
    fi

    if grep -q "^kind:[[:space:]]*Secret" "${path}" 2>/dev/null; then
        if [[ "${file}" != gitops/secrets/* ]]; then
            add_finding \
                "warning" \
                "secret_manifest_location" \
                "${file}" \
                "kubernetes secret manifest outside approved gitops/secrets path"
        fi
    fi
done

# ============================================================
# 6. PLAINTEXT SECRET EXPOSURE
# ============================================================

log_info "detecting plaintext credential exposure"

scan_for_plaintext_secrets() {
    local file="$1"

    local path
    path="$(resolve_path "${file}")"

    [[ ! -f "${path}" ]] && return
    TOTAL_CHECKED=$((TOTAL_CHECKED + 1))
    #((TOTAL_CHECKED++))

    if grep -Eqi \
        '(password|token|secret|api[_-]?key)[[:space:]]*[:=][[:space:]]*["'"'"']?[A-Za-z0-9\/+=._-]{8,}' \
        "${path}" 2>/dev/null; then

        add_finding \
            "warning" \
            "plaintext_credential" \
            "${file}" \
            "possible plaintext credential detected"
    fi
}

for file in "${WORKFLOWS[@]}"; do
    scan_for_plaintext_secrets "${file}"
done

for file in "${SHELL_SCRIPTS[@]}"; do
    scan_for_plaintext_secrets "${file}"
done

# ============================================================
# OUTPUT
# ============================================================

log_info "writing security evidence to ${OUTPUT_FILE}"

if [[ ${#FINDINGS[@]} -eq 0 ]]; then
    FINDINGS_JSON='[]'
else
    FINDINGS_JSON="$(
        printf '%s\n' "${FINDINGS[@]}" \
            | jq -s .
    )"
fi

cat > "${OUTPUT_FILE}" <<EOF
{
  "module": "${MODULE_NAME}",
  "script": "${SCRIPT_NAME}",
  "timestamp": "${TIMESTAMP}",
  "status": "${STATUS}",

  "summary": {
    "total_checked": ${TOTAL_CHECKED},
    "findings": ${#FINDINGS[@]},
    "errors": ${#ERRORS[@]},
    "warnings": ${#WARNINGS[@]}
  },

  "errors": $(json_errors),
  "warnings": $(json_warnings),

  "findings": ${FINDINGS_JSON}
}
EOF

log_info "security engine completed"
log_info "output written to ${OUTPUT_FILE}"
log_info "status=${STATUS}"

exit 0
