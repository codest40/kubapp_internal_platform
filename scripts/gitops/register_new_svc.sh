#!/bin/bash
set -euo pipefail
trap 'rm -f "${TMP_FILE:-}"' EXIT

# =========================================
# Ingress Service Manager (ADD / REMOVE)
#   register_new_svc.sh <service> <env>
#   register_new_svc.sh add <service> <env>
#   register_new_svc.sh remove <service> <env>
# =========================================

ACTION="${1:-}"
SERVICE_NAME="${2:-}"
ENV="${3:-dev}"
DOMAIN="${DOMAIN:-}"
CERT_ARN="${CERT_ARN:-}"
PORT="${SERVICE_PORT:-80}"
BACKEND_SERVICE="${BACKEND_SERVICE:-}"
TYPE="${SERVICE_TYPE:-}"

VALUES_FILE="gitops/ingress/${ENV}/values.yaml"
TMP_FILE="/tmp/ingress-values-${ENV}-$$.yaml"
BACKEND_FILE="gitops/ingress/${ENV}/monitoring.yaml"
ARGOCD_FILE="gitops/ingress/${ENV}/argocd.yaml"

# -----------------------------------------
# Normalize legacy usage
# -----------------------------------------
if [[ "$ACTION" != "add" && "$ACTION" != "remove" ]]; then
  ENV="${2:-dev}"
  SERVICE_NAME="$ACTION"
  ACTION="add"
fi

if [[ -z "$SERVICE_NAME" ]]; then
  echo "Usage:"
  echo "  $0 <service> [env]"
  echo "  $0 add <service> [env]"
  echo "  $0 remove <service> [env]"
  exit 1
fi

# -----------------------------------------
# Required variables
# -----------------------------------------
if [[ "$ACTION" == "add" ]]; then
  ARR=("ACTION" "SERVICE_NAME" "ENV" "DOMAIN" "CERT_ARN" "PORT" "VALUES_FILE")
else
  ARR=("ACTION" "SERVICE_NAME" "ENV" "VALUES_FILE")
fi

for var in "${ARR[@]}"; do
  value="${!var}"

  if [[ -z "$value" ]]; then
    echo "❌ $var required"
    exit 1
  fi

  export "$var=$value"
done

# Validate port only for add
if [[ "$ACTION" == "add" ]]; then
  [[ "$PORT" =~ ^[0-9]+$ && "$PORT" -ge 1 && "$PORT" -le 65535 ]] || {
    echo "❌ Invalid PORT: $PORT"
    exit 1
  }
fi

line() {
  printf '%*s\n' "${1:-60}" '' | tr ' ' '#'
  echo ">>> SCRIPT: $0 <<<"
}

sanitize() {
  echo "$1" | tr '_' '-' | tr '[:upper:]' '[:lower:]'
}

is_backend_service() {
  [[ "$TYPE" == "Backend" ]] &&
  [[ -n "$BACKEND_SERVICE" ]] &&
  [[ "$BACKEND_SERVICE" != "null" ]]
}

is_argocd() {
  [[ "$TYPE" == "Backend" ]] &&
  [[ "$SERVICE_NAME" == "argocd" ]]
}

line
echo "ACTION : $ACTION"
echo "SERVICE: $SERVICE_NAME"
echo "SERVICE TYPE: $TYPE"
echo "SERVICE PORT: $PORT"
if is_backend_service; then
  echo "BACKEND SERVICE: $BACKEND_SERVICE"
  if is_argocd; then
    NS="argocd"
    USE_FILE="$ARGOCD_FILE"
  else
    USE_FILE="$BACKEND_FILE"
    NS="monitoring"
  fi
else
  USE_FILE="$VALUES_FILE"
  NS="$ENV"
fi
export NS="$NS"
echo "ENV    : $ENV"
echo "NAMESPACE: $NS"
echo "FILE   : $USE_FILE"
echo "TMP    : $TMP_FILE"
echo "================================="

# -----------------------------------------
# Preconditions
# -----------------------------------------

command -v yq >/dev/null 2>&1 || { echo "yq is required"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required"; exit 1; }

if [[ ! -f "$USE_FILE" ]]; then
  echo "❌  Ingress file not found: $USE_FILE"
  touch "$USE_FILE"
fi

# -----------------------------------------
# BOOTSTRAP TEMP STATE
# -----------------------------------------
cp "$USE_FILE" "$TMP_FILE"

# INGRESS DYNAMIC CONFIGURATION (ADD ONLY)
if [[ "$ACTION" == "add" ]]; then
  yq e -i '
    .ingress.baseDomain = strenv(DOMAIN)
    | .ingress.certificateArn = strenv(CERT_ARN)
    | .ingress.name = (.ingress.name // ("kubapp-" + strenv(NS) + "-alb"))
    | .ingress.className = (.ingress.className // "alb")
    | .ingress.enableSubdomainRouting = (.ingress.enableSubdomainRouting // true)
    | .ingress.annotations.listenPorts = [
        {"HTTP": 80},
        {"HTTPS": 443}
      ]
  ' "$TMP_FILE"

  if yq e '.ingress.annotations.listenPorts | type' "$TMP_FILE" | grep -q '!!str'; then
    echo "❌ listenPorts must NOT be a string"
    exit 1
  fi
fi

# Ensure services array exists
yq e -i '.services = (.services // [])' "$TMP_FILE"

# Normalize service entries
yq e -i '
  .services |= map(
    .enabled = (.enabled // true) |
    .port = (.port // 80)
  )
' "$TMP_FILE"

# Keep only enabled services
yq e -i '.services |= map(select(.enabled == true))' "$TMP_FILE"

SERVICE_NAME="$(sanitize "$SERVICE_NAME")"
export SERVICE_NAME

# =========================================
# VALIDATION FUNCTIONS
# =========================================

validate_schema() {
  echo "Validating ingress schema..."

  yq e '.ingress.baseDomain' "$TMP_FILE" | grep -q . || {
    echo "❌ baseDomain missing"
    exit 1
  }

  yq e '.ingress.name' "$TMP_FILE" | grep -q . || {
    echo "❌ ingress name missing"
    exit 1
  }

  [[ $(yq e '.services | length' "$TMP_FILE") -gt 0 ]] || {
    echo "❌ No services defined"
    exit 1
  }
}

validate_listen_ports() {
  echo "Validating listenPorts..."

  TYPE=$(yq e '.ingress.annotations.listenPorts | type' "$TMP_FILE")

  if [[ "$TYPE" != "!!seq" ]]; then
    echo "❌ listenPorts must be a YAML array"
    exit 1
  fi

  HTTP=$(yq e '.ingress.annotations.listenPorts[] | select(has("HTTP")) | .HTTP' "$TMP_FILE" | head -n1)
  HTTPS=$(yq e '.ingress.annotations.listenPorts[] | select(has("HTTPS")) | .HTTPS' "$TMP_FILE" | head -n1)

  [[ "$HTTP" == "80" ]] || {
    echo "❌ HTTP must be 80"
    exit 1
  }

  [[ "$HTTPS" == "443" ]] || {
    echo "❌ HTTPS must be 443"
    exit 1
  }

  echo "✅ listenPorts valid"
}

validate_https_requirements() {
  echo "Validating HTTPS config..."

  if yq e '.ingress.annotations.listenPorts[] | has("HTTPS")' "$TMP_FILE" | grep -q true; then
    yq e '.ingress.certificateArn' "$TMP_FILE" | grep -q . || {
      echo "❌ HTTPS enabled but certificateArn missing"
      exit 1
    }
  fi
}

# =========================================
# SERVICE OPERATIONS
# =========================================

build_desired_service() {
  if [[ -z "${SERVICE_NAME:-}" ]]; then
    echo "❌ SERVICE_NAME is required"
    exit 1
  fi

  if [[ -z "${PORT:-}" ]]; then
    echo "❌ PORT is required"
    exit 1
  fi

  if is_backend_service && [[ -z "${BACKEND_SERVICE:-}" ]]; then
    echo "❌ BACKEND_SERVICE is required for backend services"
    exit 1
  fi

  if is_backend_service; then
    jq -n \
      --arg name "$SERVICE_NAME" \
      --argjson port "$PORT" \
      --arg backend "$BACKEND_SERVICE" \
      '{
        name: $name,
        enabled: true,
        port: $port,
        backend: {
          service: $backend
        }
      }'
  else
    jq -n \
      --arg name "$SERVICE_NAME" \
      --argjson port "$PORT" \
      '{
        name: $name,
        enabled: true,
        port: $port
      }'
  fi
}

get_current_service() {
  yq e -o=json '.services[] | select(.name == strenv(SERVICE_NAME))' "$TMP_FILE" 2>/dev/null || true
}

get_service_index() {
  local idx

  idx="$(yq e '.services | to_entries[] | select(.value.name == strenv(SERVICE_NAME)) | .key' "$TMP_FILE" 2>/dev/null || true)"

  if [[ -n "${idx:-}" && "${idx:-}" != "null" ]]; then
    echo "$idx"
  fi
}

compare_objects() {
  local current_json="$1"
  local desired_json="$2"

  local all_keys
  local changed=0

  # Collect every scalar path from BOTH objects.
  all_keys="$(
    {
      echo "$current_json" | jq -r 'paths(scalars) | map(tostring) | join(".")'
      echo "$desired_json" | jq -r 'paths(scalars) | map(tostring) | join(".")'
    } | sort -u
  )"

  while IFS= read -r key; do
    [[ -z "${key:-}" ]] && continue

    local current_value desired_value

    current_value="$(
      echo "$current_json" |
      jq -r --arg path "$key" '
        ($path | split(".")) as $p
        | getpath($p) // null
      ' 2>/dev/null || true
    )"

    desired_value="$(
      echo "$desired_json" |
      jq -r --arg path "$key" '
        ($path | split(".")) as $p
        | getpath($p) // null
      ' 2>/dev/null || true
    )"

    # Desired value missing is a hard error.
    if [[ -z "${desired_value:-}" || "${desired_value:-}" == "null" ]]; then
      echo "❌ Desired value missing for key: $key"
      exit 1
    fi

    # Missing current value is treated as drift and corrected.
    if [[ -z "${current_value:-}" ]]; then
      current_value="null"
    fi

    if [[ "$current_value" != "$desired_value" ]]; then
      changed=1
      echo "DIFF: $key"
      echo "  Current: $current_value"
      echo "  Desired: $desired_value"
    fi
  done <<< "$all_keys"

  return "$changed"
}

needs_update() {
  local current_json desired_json

  current_json="$(get_current_service)"
  desired_json="$(build_desired_service)"

  # Service not found → create it.
  if [[ -z "${current_json:-}" || "${current_json:-}" == "null" ]]; then
    echo "Service does not exist. It will be created."
    return 0
  fi

  if compare_objects "$current_json" "$desired_json"; then
    # No differences
    return 1
  else
    # Differences detected
    return 0
  fi
}

apply_service() {
  local desired_json
  local index

  desired_json="$(build_desired_service)"

  if ! needs_update; then
    echo "✅ Service $SERVICE_NAME already matches desired state. No changes required."
    return 0
  fi

  echo "Reconciling service: $SERVICE_NAME"

  index="$(get_service_index)"

  if [[ -n "${index:-}" ]]; then
    echo "Updating existing service by replacing full object..."

    yq e -i "
      .services[$index] = $desired_json
    " "$TMP_FILE"
  else
    echo "Adding new service..."

    yq e -i "
      .services += [$desired_json]
    " "$TMP_FILE"
  fi
}

remove_service() {
  EXISTS=$(yq e ".services[] | select(.name == strenv(SERVICE_NAME)) | .name" "$TMP_FILE" | wc -l)

  if [[ "$EXISTS" -eq 0 ]]; then
    echo "Service not found: $SERVICE_NAME"
    return 0
  fi

  echo "Removing service: $SERVICE_NAME"

  yq e -i '
    .services |= map(select(.name != strenv(SERVICE_NAME)))
  ' "$TMP_FILE"
}

# =========================================
# EXECUTION FLOW
# =========================================

case "$ACTION" in
  add) apply_service ;;
  remove) remove_service ;;
  *) echo "Invalid action"; exit 1 ;;
esac

# =========================================
# VALIDATION
# =========================================

validate_schema
validate_listen_ports
validate_https_requirements

echo "Running YAML validation..."
yq e '.' "$TMP_FILE" >/dev/null

echo "Running final structural validation..."

yq e '
  .ingress.baseDomain != null and
  .ingress.name != null and
  (.services | length > 0)
' "$TMP_FILE" | grep -q true || {
  echo "❌ Ingress schema invalid"
  exit 1
}

# =========================================
# ATOMIC APPLY
# =========================================

echo "Applying changes atomically..."


cp "$USE_FILE" "${USE_FILE}.bak"
mv "$TMP_FILE" "$USE_FILE"

echo "Update complete"
echo "---------------------------------"
cat "$USE_FILE"
echo "---------------------------------"
