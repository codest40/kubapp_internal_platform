#!/bin/bash

# ============================================================
# KUBAPP — CODEBASE DISCOVERY ENGINE (v2)
# ROLE: SINGLE SOURCE OF TRUTH INVENTORY BUILDER
# ============================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/runtime.sh"
source "${CODEBASE_ROOT}/lib/json.sh"

MODULE_NAME="Discovery"
INVENTORY_FILE="${EVIDENCE_DIR}/inventory.json"

log_info "starting discovery engine"
build_find_excludes
# ============================================================
# VALIDATION
# ============================================================

require_binary "jq"
require_binary "find"

# ============================================================
# STATE
# ============================================================

ALL_FILES=()

TF_ROOTS=()
TF_MODULES=()

SHELL_SCRIPTS=()
WORKFLOWS=()

K8S_MANIFESTS=()
DOCKER_COMPOSE=()
DOCKERFILES=()

HELM_VALUES=()
CHART_FILES=()

PROMETHEUS_CONFIGS=()
OPERATIONAL_CONFIGS=()

ARGOCD_CONFIGS=()
REPO_SECRETS=()

DOCUMENTATION=()
APPLICATION_CONFIGS=()

# ============================================================
# TERRAFORM ROOTS
# ============================================================

if ! mapfile -t TF_ROOTS < <(
    find "${PROJECT_ROOT}" -type f -name "*.tf" \
        "${EXCLUDE_ARGS[@]}" \
        ! -path "*/modules/*" \
        -printf '%h\n' \
        | sort -u \
        | while read -r dir; do
            if [[ \
                -f "${dir}/providers.tf" || \
                -f "${dir}/provider.tf" || \
                -f "${dir}/backend.tf" || \
                -f "${dir}/versions.tf"
            ]]; then
                echo "${dir#"${PROJECT_ROOT}/"}"
            fi
        done
); then
    STATUS="fail"
    ERRORS+=("terraform root discovery failed")
fi

mapfile -t ALL_FILES < <(
    find "${PROJECT_ROOT}" \
         "${EXCLUDE_ARGS[@]}" \
        -type f \
        -print \
        | sed "s|${PROJECT_ROOT}/||" \
        | sort -u
)

# ============================================================
# TERRAFORM MODULES
# ============================================================

if ! mapfile -t TF_MODULES < <(
    find "${PROJECT_ROOT}/iac" -type f -name "*.tf" \
        "${EXCLUDE_ARGS[@]}" \
        2>/dev/null \
        | grep "/modules/" \
        | xargs -r dirname \
        | sort -u \
        | sed "s|${PROJECT_ROOT}/||"
); then
    STATUS="fail"
    ERRORS+=("terraform module discovery failed")
fi


# SHELL SCRIPTS
# ============================================================

mapfile -t SHELL_SCRIPTS < <(
    find "${PROJECT_ROOT}" \
        "${EXCLUDE_ARGS[@]}" \
        -type f -name "*.sh" \
        | sed "s|${PROJECT_ROOT}/||" \
        | sort -u
)

# ============================================================
# WORKFLOWS
# ============================================================

mapfile -t WORKFLOWS < <(
    find "${PROJECT_ROOT}/.github/workflows" \
        -type f \( -name "*.yml" -o -name "*.yaml" \) \
        2>/dev/null \
        | sed "s|${PROJECT_ROOT}/||" \
        | sort -u
)

# ============================================================
# DOCKERFILES
# ============================================================

mapfile -t DOCKERFILES < <(
    find "${PROJECT_ROOT}" \
        "${EXCLUDE_ARGS[@]}" \
        -name "Dockerfile" \
        | sed "s|${PROJECT_ROOT}/||" \
        | sort -u
)

# ============================================================
# DOCKER COMPOSE
# ============================================================

mapfile -t DOCKER_COMPOSE < <(
    find "${PROJECT_ROOT}" \
        "${EXCLUDE_ARGS[@]}" \
        \( -name "docker-compose*.yml" -o -name "docker-compose*.yaml" \) \
        | sed "s|${PROJECT_ROOT}/||" \
        | sort -u
)

# ============================================================
# YAML DISCOVERY (CLASSIFICATION LAYER)
# ============================================================

while IFS= read -r file; do
    [[ -z "$file" ]] && continue

    rel="${file#"${PROJECT_ROOT}/"}"

    # Kubernetes manifests
    if grep -q "^apiVersion:" "$file" && grep -q "^kind:" "$file"; then
        K8S_MANIFESTS+=("$rel")
        continue
    fi

    # Helm values
    if [[ "$file" == *values.yaml ]]; then
        HELM_VALUES+=("$rel")
        continue
    fi

    # Charts
    if [[ "$(basename "$file")" == "Chart.yaml" ]]; then
        CHART_FILES+=("$rel")
        continue
    fi

    # Prometheus configs
    if [[ "$file" == *prometheus* ]]; then
        PROMETHEUS_CONFIGS+=("$rel")
        continue
    fi

    # Operational configs
    if [[ "$file" == *.sops.yaml || "$file" == *.checkov.yaml ]]; then
        OPERATIONAL_CONFIGS+=("$rel")
        continue
    fi

    # Grafana / observability
    if [[ "$file" == *grafana* || "$file" == *observability* ]]; then
        OPERATIONAL_CONFIGS+=("$rel")
        continue
    fi

    # Application configs
    if [[ "$file" == *kubapp.yml ]]; then
        APPLICATION_CONFIGS+=("$rel")
        continue
    fi

done < <(
    find "${PROJECT_ROOT}" \
        "${EXCLUDE_ARGS[@]}" \
        \( -name "*.yml" -o -name "*.yaml" \)
)

# ============================================================
# PROMETHEUS (dedup safety)
# ============================================================

PROMETHEUS_CONFIGS=($(printf "%s\n" "${PROMETHEUS_CONFIGS[@]}" | sort -u))

# ============================================================
# ARGOCD CONFIGS
# ============================================================

mapfile -t ARGOCD_CONFIGS < <(
    find "${PROJECT_ROOT}/gitops/argocd" \
        -type f \( -name "*.yml" -o -name "*.yaml" \) \
        2>/dev/null \
        | sed "s|${PROJECT_ROOT}/||" \
        | sort -u
)

# ============================================================
# REPO SECRETS
# ============================================================

mapfile -t REPO_SECRETS < <(
    find "${PROJECT_ROOT}" \
        "${EXCLUDE_ARGS[@]}" \
        -type f \
        \( -name "*.enc" -o -path "*/gitops/secrets*" -o -path "/docker/*/secrets.yml" -o -path "/docker/*/secrets.yaml" \) \
        | sed "s|${PROJECT_ROOT}/||" \
        | sort -u
)

# ============================================================
# DOCUMENTATION
# ============================================================

mapfile -t DOCUMENTATION < <(
    find "${PROJECT_ROOT}/docs" \
        -type f 2>/dev/null \
        | sed "s|${PROJECT_ROOT}/||" \
        | sort -u
)

# ============================================================
# OUTPUT
# ============================================================

log_info "writing inventory evidence"

cat > "${INVENTORY_FILE}" <<EOF
{
  "module": "${MODULE_NAME}",
  "script": "${SCRIPT_NAME}",
  "timestamp": "${TIMESTAMP}",
  "status": "${STATUS}",

  "errors": $(json_errors),
  "warnings": $(json_warnings),

  "repository": "kubapp",

  "files": {
    "all_files": $(json_array "${ALL_FILES[@]}")
  },

  "terraform": {
    "roots": $(json_array "${TF_ROOTS[@]}"),
    "modules": $(json_array "${TF_MODULES[@]}")
  },

  "shell_scripts": $(json_array "${SHELL_SCRIPTS[@]}"),
  "workflows": $(json_array "${WORKFLOWS[@]}"),

  "repo_secrets": $(json_array "${REPO_SECRETS[@]}"),

  "gitops": {
    "argocd_configs": $(json_array "${ARGOCD_CONFIGS[@]}")
  },

  "yaml": {
    "kubernetes_manifests": $(json_array "${K8S_MANIFESTS[@]}"),
    "helm_values": $(json_array "${HELM_VALUES[@]}"),
    "chart_files": $(json_array "${CHART_FILES[@]}"),
    "docker_files": $(json_array "${DOCKERFILES[@]}"),
    "docker_compose": $(json_array "${DOCKER_COMPOSE[@]}"),
    "prometheus_configs": $(json_array "${PROMETHEUS_CONFIGS[@]}"),
    "operational_configs": $(json_array "${OPERATIONAL_CONFIGS[@]}"),
    "application_configs": $(json_array "${APPLICATION_CONFIGS[@]}")
  },

  "documentation": $(json_array "${DOCUMENTATION[@]}"),

  "statistics": {
    "all_files_count": ${#ALL_FILES[@]},
    "terraform_root_count": ${#TF_ROOTS[@]},
    "terraform_module_count": ${#TF_MODULES[@]},
    "shell_script_count": ${#SHELL_SCRIPTS[@]},
    "workflow_count": ${#WORKFLOWS[@]},
    "dockerfile_count": ${#DOCKERFILES[@]},
    "k8s_manifest_count": ${#K8S_MANIFESTS[@]},
    "argocd_config_count": ${#ARGOCD_CONFIGS[@]},
    "chart_file_count": ${#CHART_FILES[@]}
  }
}

EOF

log_info "discovery engine completed"
log_info "inventory written to ${INVENTORY_FILE}"
