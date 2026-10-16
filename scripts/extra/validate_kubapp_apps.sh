#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"

if [[ -z "$ROOT" ]]; then
    echo "[ERROR] Unable to determine project root." >&2
    exit 1
fi

cd "$ROOT"

DOCKER_DIR="$ROOT/docker"

# ============================================================
# HELPERS
# ============================================================

fail() {
    echo "[ERROR] $*" >&2
    exit 1
}

log_info() {
    echo "[INFO] $*"
}

log_ok() {
    echo "[INFO] [PASS] $*"
}

is_nonempty() {
    local value="${1:-}"
    value="${value//[[:space:]]/}"
    [[ -n "$value" ]]
}

yaml_type() {
    yq e "$2 | type" "$1"
}

check_yaml() {
    local file="$1"

    yq e '.' "$file" >/dev/null 2>&1 \
        || fail "Invalid YAML: ${file#$ROOT/}"
}

# Resolve a configured path relative to the application directory.
# If it does not exist there, try the repository root.
resolve_app_path() {
    local app_dir="$1"
    local configured_path="$2"

    if [[ "$configured_path" = /* ]]; then
        printf '%s\n' "$configured_path"
    elif [[ -e "$app_dir/$configured_path" ]]; then
        printf '%s\n' "$app_dir/$configured_path"
    else
        printf '%s\n' "$ROOT/$configured_path"
    fi
}

# Require a YAML value to be a nonempty string.
require_string() {
    local file="$1"
    local expression="$2"
    local label="$3"
    local type
    local value

    type="$(yaml_type "$file" "$expression")"

    [[ "$type" == "!!str" ]] \
        || fail "$label must be a string."

    value="$(yq e -r "$expression" "$file")"

    is_nonempty "$value" \
        || fail "$label must not be empty."
}

# Validate a list of nonempty strings.
validate_string_list() {
    local file="$1"
    local expression="$2"
    local label="$3"
    local allow_empty="${4:-false}"
    local count
    local index
    local item
    local type

    type="$(yaml_type "$file" "$expression")"

    [[ "$type" == "!!seq" ]] \
        || fail "$label must be a list."

    count="$(yq e "$expression | length" "$file")"

    if [[ "$allow_empty" != "true" && "$count" -eq 0 ]]; then
        fail "$label must contain at least one entry."
    fi

    for ((index = 0; index < count; index++)); do
        type="$(yaml_type "$file" "$expression[$index]")"

        [[ "$type" == "!!str" ]] \
            || fail "$label[$index] must be a string."

        item="$(yq e -r "$expression[$index]" "$file")"

        is_nonempty "$item" \
            || fail "$label[$index] must not be empty."
    done
}

# Validate a mapping whose values are lists of command strings.
validate_command_map() {
    local file="$1"
    local expression="$2"
    local label="$3"
    local allow_empty_map="${4:-false}"
    local count
    local stage
    local stage_type
    local stage_count
    local index
    local item
    local item_type

    stage_type="$(yaml_type "$file" "$expression")"

    [[ "$stage_type" == "!!map" ]] \
        || fail "$label must be a mapping."

    count="$(yq e "$expression | length" "$file")"

    if [[ "$allow_empty_map" != "true" && "$count" -eq 0 ]]; then
        fail "$label must contain at least one stage."
    fi

    while IFS= read -r stage; do
        [[ -n "$stage" ]] \
            || fail "$label contains an empty stage name."

        stage_type="$(
            STAGE="$stage" \
                yq e "$expression[strenv(STAGE)] | type" "$file"
        )"

        [[ "$stage_type" == "!!seq" ]] \
            || fail "$label.$stage must be a list."

        stage_count="$(
            STAGE="$stage" \
                yq e "$expression[strenv(STAGE)] | length" "$file"
        )"

        # An empty security_env CI stage is explicitly permitted.
        if [[ "$stage" == "security_env" && "$stage_count" -eq 0 ]]; then
            log_info "$label.security_env is empty; allowed."
            continue
        fi

        (( stage_count > 0 )) \
            || fail "$label.$stage must not be empty."

        for ((index = 0; index < stage_count; index++)); do
            item_type="$(
                STAGE="$stage" INDEX="$index" \
                    yq e "$expression[strenv(STAGE)][env(INDEX)] | type" "$file"
            )"

            [[ "$item_type" == "!!str" ]] \
                || fail "$label.$stage[$index] must be a string."

            item="$(
                STAGE="$stage" INDEX="$index" \
                    yq e -r "$expression[strenv(STAGE)][env(INDEX)]" "$file"
            )"

            is_nonempty "$item" \
                || fail "$label.$stage[$index] must not be empty."
        done

        log_ok "$label.$stage"
    done < <(
        yq e -r "$expression | keys | .[]" "$file"
    )
}

# Validate a configured file path and optionally validate it as YAML.
validate_configured_file() {
    local app_dir="$1"
    local configured_path="$2"
    local label="$3"
    local validate_as_yaml="${4:-false}"
    local resolved

    is_nonempty "$configured_path" \
        || fail "$label must not be empty."

    resolved="$(resolve_app_path "$app_dir" "$configured_path")"

    [[ -f "$resolved" ]] \
        || fail "$label does not exist: $configured_path"

    if [[ "$validate_as_yaml" == "true" ]]; then
        check_yaml "$resolved"
    fi

    log_ok "$label: $configured_path"
}

# ============================================================
# PRECHECKS
# ============================================================

command -v yq >/dev/null 2>&1 \
    || fail "yq is required but was not found."

[[ -d "$DOCKER_DIR" ]] \
    || fail "Missing docker directory: $DOCKER_DIR"

echo
echo "=================================================="
echo "[INFO] KUBAPP APPLICATION VALIDATION"
echo "[INFO] DIRECTORY: $DOCKER_DIR"
echo "=================================================="
echo

# ============================================================
# DISCOVER APPLICATIONS
# ============================================================

mapfile -d '' -t APP_DIRS < <(
    find "$DOCKER_DIR" \
        -mindepth 1 \
        -maxdepth 1 \
        -type d \
        -name '*_app' \
        -print0 |
        sort -z
)

((${#APP_DIRS[@]} > 0)) \
    || fail "No KUBAPP applications found. Application directories must end in '_app'."

log_info "Found ${#APP_DIRS[@]} application(s)"

for app_dir in "${APP_DIRS[@]}"; do
    log_info "$(basename "$app_dir")"
done

echo

# ============================================================
# VALIDATE APPLICATIONS
# ============================================================

for APP_DIR in "${APP_DIRS[@]}"; do

    APP_NAME="$(basename "$APP_DIR")"

    echo
    echo "=================================================="
    log_info "APPLICATION: $APP_NAME"
    echo "=================================================="

    # --------------------------------------------------------
    # FIND CI CONFIGURATIONS RECURSIVELY
    # --------------------------------------------------------

    mapfile -d '' -t CI_FILES < <(
        find "$APP_DIR" \
            -type f \
            -name 'ci.yml' \
            -print0 |
            sort -z
    )

    ((${#CI_FILES[@]} > 0)) \
        || fail "$APP_NAME: at least one ci.yml must exist somewhere inside the application directory."

    log_info "Found ${#CI_FILES[@]} ci.yml file(s)."

    # --------------------------------------------------------
    # VALIDATE EACH CI CONFIGURATION
    # --------------------------------------------------------

    for CI_FILE in "${CI_FILES[@]}"; do

        CI_RELATIVE="${CI_FILE#$ROOT/}"

        echo
        log_info "Validating $CI_RELATIVE"

        check_yaml "$CI_FILE"

        # The root of ci.yml must be a mapping.
        ROOT_TYPE="$(yaml_type "$CI_FILE" '.')"

        [[ "$ROOT_TYPE" == "!!map" ]] \
            || fail "$CI_RELATIVE: the YAML document must be a mapping."

        # ----------------------------------------------------
        # ALLOWED TOP-LEVEL FIELDS
        # ----------------------------------------------------

        ALLOWED_FIELDS=(
            runtime
            file_paths
            use_script
            ci_scripts
            ci_commands
            extra_ci_commands
            security_env
            extra_ci_config
        )

        while IFS= read -r field; do
            [[ -n "$field" ]] || continue

            allowed=false

            for expected in "${ALLOWED_FIELDS[@]}"; do
                if [[ "$field" == "$expected" ]]; then
                    allowed=true
                    break
                fi
            done

            [[ "$allowed" == "true" ]] \
                || fail "$CI_RELATIVE: unsupported top-level field '$field'."
        done < <(
            yq e -r 'keys | .[]' "$CI_FILE"
        )

        # ----------------------------------------------------
        # RUNTIME: REQUIRED STRING
        # ----------------------------------------------------

        require_string "$CI_FILE" '.runtime' "$CI_RELATIVE: runtime"

        RUNTIME="$(yq e -r '.runtime' "$CI_FILE")"

        log_ok "Runtime: $RUNTIME"

        # ----------------------------------------------------
        # FILE PATHS: OPTIONAL MAPPING
        # ----------------------------------------------------

        SECRET_PATH=""

        if [[ "$(yaml_type "$CI_FILE" '.file_paths')" != "!!null" ]]; then

            [[ "$(yaml_type "$CI_FILE" '.file_paths')" == "!!map" ]] \
                || fail "$CI_RELATIVE: file_paths must be a mapping."

            FILE_PATH_FIELDS=(
                manifest_files
                docker_file
                kubapp_file
                secret_file
            )

            while IFS= read -r field; do
                [[ -n "$field" ]] || continue

                allowed=false

                for expected in "${FILE_PATH_FIELDS[@]}"; do
                    if [[ "$field" == "$expected" ]]; then
                        allowed=true
                        break
                    fi
                done

                [[ "$allowed" == "true" ]] \
                    || fail "$CI_RELATIVE: unsupported file_paths field '$field'."
            done < <(
                yq e -r '.file_paths | keys | .[]' "$CI_FILE"
            )

            if [[ "$(yaml_type "$CI_FILE" '.file_paths.manifest_files')" != "!!null" ]]; then

                validate_string_list \
                    "$CI_FILE" \
                    '.file_paths.manifest_files' \
                    "$CI_RELATIVE: file_paths.manifest_files"

                count="$(yq e '.file_paths.manifest_files | length' "$CI_FILE")"

                for ((i = 0; i < count; i++)); do
                    path="$(yq e -r ".file_paths.manifest_files[$i]" "$CI_FILE")"

                    validate_configured_file \
                        "$APP_DIR" "$path" \
                        "$CI_RELATIVE: manifest_files[$i]"
                done
            fi

            if [[ "$(yaml_type "$CI_FILE" '.file_paths.docker_file')" != "!!null" ]]; then
                path="$(yq e -r '.file_paths.docker_file' "$CI_FILE")"

                validate_configured_file \
                    "$APP_DIR" "$path" \
                    "$CI_RELATIVE: docker_file"
            else
                [[ -f "$APP_DIR/Dockerfile" ]] \
                    || fail "$APP_NAME: Dockerfile is required at the application root unless file_paths.docker_file is configured."

                log_ok "Dockerfile found"
            fi

            if [[ "$(yaml_type "$CI_FILE" '.file_paths.kubapp_file')" != "!!null" ]]; then
                path="$(yq e -r '.file_paths.kubapp_file' "$CI_FILE")"

                validate_configured_file \
                    "$APP_DIR" "$path" \
                    "$CI_RELATIVE: kubapp_file" true
            fi

            if [[ "$(yaml_type "$CI_FILE" '.file_paths.secret_file')" != "!!null" ]]; then
                SECRET_PATH="$(yq e -r '.file_paths.secret_file' "$CI_FILE")"

                is_nonempty "$SECRET_PATH" \
                    || fail "$CI_RELATIVE: file_paths.secret_file must not be empty."
            fi

            log_ok "file_paths structure"
        else
            [[ -f "$APP_DIR/Dockerfile" ]] \
                || fail "$APP_NAME: Dockerfile is required."
            [[ -s "$APP_DIR/Dockerfile" ]] \
                || fail "$APP_NAME: Nonempty Dockerfile is required."

            log_ok "Dockerfile found"
        fi

        # ----------------------------------------------------
        # USE_SCRIPT: OPTIONAL BOOLEAN
        # ----------------------------------------------------

        USE_SCRIPT=false

        if [[ "$(yaml_type "$CI_FILE" '.use_script')" != "!!null" ]]; then

            USE_SCRIPT_TYPE="$(yaml_type "$CI_FILE" '.use_script')"

            [[ "$USE_SCRIPT_TYPE" == "!!bool" ]] \
                || fail "$CI_RELATIVE: use_script must be a boolean."

            USE_SCRIPT="$(yq e -r '.use_script' "$CI_FILE")"
        fi

        # ----------------------------------------------------
        # CI SCRIPTS: OPTIONAL LIST, REQUIRED WHEN TRUE
        # ----------------------------------------------------

        if [[ "$(yaml_type "$CI_FILE" '.ci_scripts')" != "!!null" ]]; then

            validate_string_list \
                "$CI_FILE" \
                '.ci_scripts' \
                "$CI_RELATIVE: ci_scripts"

            count="$(yq e '.ci_scripts | length' "$CI_FILE")"

            for ((i = 0; i < count; i++)); do
                path="$(yq e -r ".ci_scripts[$i]" "$CI_FILE")"

                validate_configured_file \
                    "$APP_DIR" "$path" \
                    "$CI_RELATIVE: ci_scripts[$i]"
            done

        elif [[ "$USE_SCRIPT" == "true" ]]; then
            fail "$CI_RELATIVE: use_script is true, so ci_scripts is required."
        fi

        # ----------------------------------------------------
        # CI COMMANDS: REQUIRED UNLESS USE_SCRIPT IS TRUE
        # ----------------------------------------------------

        if [[ "$(yaml_type "$CI_FILE" '.ci_commands')" != "!!null" ]]; then

            validate_command_map \
                "$CI_FILE" \
                '.ci_commands' \
                "$CI_RELATIVE: ci_commands"

        elif [[ "$USE_SCRIPT" != "true" ]]; then
            fail "$CI_RELATIVE: ci_commands is required when use_script is false or omitted."
        fi

        # ----------------------------------------------------
        # EXTRA CI COMMANDS: OPTIONAL MAPPING
        # ----------------------------------------------------

        if [[ "$(yaml_type "$CI_FILE" '.extra_ci_commands')" != "!!null" ]]; then

            validate_command_map \
                "$CI_FILE" \
                '.extra_ci_commands' \
                "$CI_RELATIVE: extra_ci_commands" true

            log_ok "extra_ci_commands structure"
        fi

        # ----------------------------------------------------
        # SECURITY ENV: OPTIONAL LIST
        # ----------------------------------------------------

        SECURITY_ENV_COUNT=0

        if [[ "$(yaml_type "$CI_FILE" '.security_env')" != "!!null" ]]; then

            validate_string_list \
                "$CI_FILE" \
                '.security_env' \
                "$CI_RELATIVE: security_env" true

            SECURITY_ENV_COUNT="$(yq e '.security_env | length' "$CI_FILE")"

            for ((i = 0; i < SECURITY_ENV_COUNT; i++)); do

                env_name="$(yq e -r ".security_env[$i]" "$CI_FILE")"

                [[ "$env_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] \
                    || fail "$CI_RELATIVE: invalid environment-variable name '$env_name'."

            done

            log_ok "security_env structure"
        fi

        # ----------------------------------------------------
        # EXTRA CI CONFIG: REQUIRED HEALTHCHECK CONFIGURATION
        # ----------------------------------------------------

        [[ "$(yaml_type "$CI_FILE" '.extra_ci_config')" == "!!map" ]] \
            || fail "$CI_RELATIVE: extra_ci_config is required and must be a mapping."

        while IFS= read -r field; do
            [[ -n "$field" ]] || continue

            [[ "$field" == "healthcheck" ]] \
                || fail "$CI_RELATIVE: unsupported extra_ci_config field '$field'."
        done < <(
            yq e -r '.extra_ci_config | keys | .[]' "$CI_FILE"
        )

        [[ "$(yaml_type "$CI_FILE" '.extra_ci_config.healthcheck')" == "!!map" ]] \
            || fail "$CI_RELATIVE: extra_ci_config.healthcheck is required and must be a mapping."

        HEALTHCHECK_FIELDS=(
            app_port
            host_port
            endpoints
            expected_status
        )

        while IFS= read -r field; do
            [[ -n "$field" ]] || continue

            allowed=false

            for expected in "${HEALTHCHECK_FIELDS[@]}"; do
                if [[ "$field" == "$expected" ]]; then
                    allowed=true
                    break
                fi
            done

            [[ "$allowed" == "true" ]] \
                || fail "$CI_RELATIVE: unsupported healthcheck field '$field'."
        done < <(
            yq e -r '.extra_ci_config.healthcheck | keys | .[]' "$CI_FILE"
        )

        for field in app_port host_port expected_status; do

            expression=".extra_ci_config.healthcheck.$field"

            [[ "$(yaml_type "$CI_FILE" "$expression")" == "!!int" ]] \
                || fail "$CI_RELATIVE: healthcheck.$field must be an integer."

            value="$(yq e -r "$expression" "$CI_FILE")"

            if [[ "$field" == "expected_status" ]]; then
                (( value >= 100 && value <= 599 )) \
                    || fail "$CI_RELATIVE: healthcheck.expected_status must be between 100 and 599."
            else
                (( value >= 1 && value <= 65535 )) \
                    || fail "$CI_RELATIVE: healthcheck.$field must be between 1 and 65535."
            fi
        done

        validate_string_list \
            "$CI_FILE" \
            '.extra_ci_config.healthcheck.endpoints' \
            "$CI_RELATIVE: healthcheck.endpoints"

        count="$(yq e '.extra_ci_config.healthcheck.endpoints | length' "$CI_FILE")"

        for ((i = 0; i < count; i++)); do
            endpoint="$(yq e -r ".extra_ci_config.healthcheck.endpoints[$i]" "$CI_FILE")"

            [[ "$endpoint" == /* ]] \
                || fail "$CI_RELATIVE: healthcheck endpoint '$endpoint' must start with '/'."
        done

        log_ok "extra_ci_config.healthcheck structure"

        # ----------------------------------------------------
        # OPTIONAL KUBAPP FILES AT THE APPLICATION ROOT
        # ----------------------------------------------------

        if [[ ! -f "$APP_DIR/kubapp.yml" && ! -f "$APP_DIR/kubapp.yaml" ]]; then
            log_info "No root-level kubapp.yml/kubapp.yaml found."
        fi

        # ----------------------------------------------------
        # SECURITY ENV REQUIRES A SECRETS FILE
        # ----------------------------------------------------

        SECRET_FOUND=false
        SECRET_CANDIDATES=()

        if [[ -n "$SECRET_PATH" ]]; then

            resolved_secret="$(resolve_app_path "$APP_DIR" "$SECRET_PATH")"

            SECRET_CANDIDATES+=("$resolved_secret")

        else

            SECRET_CANDIDATES+=(
                "$APP_DIR/secrets.yml"
                "$APP_DIR/secrets.yaml"
                "$APP_DIR/secret.yml"
                "$APP_DIR/secret.yaml"
                "$APP_DIR/.env"
            )

        fi

        for secret_file in "${SECRET_CANDIDATES[@]}"; do

            [[ -f "$secret_file" ]] || continue

            SECRET_FOUND=true

            case "$secret_file" in
                *.yml|*.yaml)
                    check_yaml "$secret_file"
                    ;;
                *.env)
                    log_info ".env found; encryption validation is handled separately."
                    ;;
            esac

            log_ok "Secret file: ${secret_file#$ROOT/}"
            break
        done

        if (( SECURITY_ENV_COUNT > 0 )); then
            [[ "$SECRET_FOUND" == "true" ]] \
                || fail "$CI_RELATIVE: security_env contains entries, but the required secrets file was not found."

            log_ok "security_env has a corresponding secrets file"

        elif [[ "$SECRET_FOUND" == "false" ]]; then
            log_info "No secret file found; optional when security_env is empty."
        fi

        log_ok "$CI_RELATIVE passed"

    done

    log_ok "$APP_NAME passed"

done

echo
echo "=================================================="
echo "[PASS] KUBAPP APPLICATION VALIDATION PASSED"
echo "=================================================="

