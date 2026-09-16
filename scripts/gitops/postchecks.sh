#!/usr/bin/env bash
set -euo pipefail

########################################
# INPUT VALIDATION
########################################
ENV="${1:?ENV required}"
DOMAIN="${2:?DOMAIN required}"

: "${ARGOCD_SERVER:?ARGOCD_SERVER not set}"
: "${ARGOCD_AUTH_TOKEN:?ARGOCD_AUTH_TOKEN not set}"

########################################
# OPTIONAL CONFIG
########################################
SUCCESS_THRESHOLD="${SUCCESS_THRESHOLD:-90}"
ATTEMPTS="${ATTEMPTS:-3}"
SLEEP="${SLEEP:-20}"
CANARY_REQUESTS="${CANARY_REQUESTS:-10}"

########################################
# PATHS
########################################
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REG_DIR="$ROOT/gitops/registry/$ENV"

[[ -d "$REG_DIR" ]] || {
  echo "❌ Registry not found: $REG_DIR"
  exit 1
}

########################################
# HEADER
########################################
echo "=================================="
echo "RUNTIME VERIFICATION"
echo "ENV: $ENV"
echo "DOMAIN: $DOMAIN"
echo "ARGOCD_SERVER: $ARGOCD_SERVER"
echo "=================================="

########################################
# SERVICE DISCOVERY
########################################
mapfile -t SERVICES < <(
  find "$REG_DIR" -name "*.json" \
    -exec jq -r '.service' {} \; \
    | sort -u
)

[[ ${#SERVICES[@]} -gt 0 ]] || {
  echo "❌ No services found"
  exit 1
}

########################################
# STATE
########################################
declare -A RESULT
declare -A FAIL_REASON
declare -A SERVICE_FILES

########################################
# PRELOAD FILE MAP
########################################
while IFS= read -r file; do
  svc="$(jq -r '.service' "$file" 2>/dev/null || true)"

  if [[ -n "$svc" && "$svc" != "null" ]]; then
    SERVICE_FILES["$svc"]="$file"
  fi
done < <(find "$REG_DIR" -name "*.json")

########################################
# HELPERS
########################################
get_file() {
  echo "${SERVICE_FILES[$1]:-}"
}

get_stack() {
  local file
  file="$(get_file "$1")"

  [[ -z "$file" ]] && {
    echo "app"
    return
  }

  jq -r '.stack // "app"' "$file"
}

get_namespace() {
  local stack
  stack="$(get_stack "$1")"

  case "$stack" in
    monitoring)
      echo "monitoring"
      ;;
    argocd)
      echo "argocd"
      ;;
    *)
      echo "$ENV"
      ;;
  esac
}

get_argocd_app() {
  local svc="$1"
  local stack

  stack="$(get_stack "$svc")"

  case "$stack" in
    monitoring)
      echo "ingress-${ENV}-monitoring"
      ;;
    argocd)
      echo "ingress-${ENV}-argocd"
      ;;
    *)
      echo "${svc}-${ENV}"
      ;;
  esac
}

get_base_path() {
  local file
  file="$(get_file "$1")"

  [[ -z "$file" ]] && {
    echo "/"
    return
  }

  jq -r '.basePath // "/"' "$file"
}

get_health_path() {
  local file
  file="$(get_file "$1")"

  [[ -z "$file" ]] && {
    echo "/health"
    return
  }

  jq -r '.healthPath // "/health"' "$file"
}

########################################
# HTTP CANARY
########################################
check_http() {
  local url="$1"
  local success=0
  local total=0
  local code

  for _ in $(seq 1 "$CANARY_REQUESTS"); do
    code=$(
      curl -ksS \
        --max-time 5 \
        -o /dev/null \
        -w "%{http_code}" \
        "$url" || echo "000"
    )

    if [[ "$code" =~ ^2 ]]; then
      ((success++))
    fi

    ((total++))
  done

  echo $(( success * 100 / total ))
}

########################################
# POD HEALTH
########################################
check_pods() {
  local svc="$1"
  local ns="$2"

  kubectl get pods -n "$ns" --no-headers 2>/dev/null \
    | grep -i "$svc" \
    | awk '{print $2 " " $3}' \
    | grep -Ev '^[0-9]+/[0-9]+ Running|Completed' \
    || true
}

########################################
# ROLLOUT CHECK
########################################
check_rollout() {
  local svc="$1"
  local ns="$2"

  kubectl get deploy -n "$ns" --no-headers 2>/dev/null \
    | grep -iq "$svc"

  if [[ $? -eq 0 ]]; then
    deploy_name="$(
      kubectl get deploy -n "$ns" --no-headers \
        | grep -i "$svc" \
        | head -1 \
        | awk '{print $1}'
    )"

    kubectl rollout status deployment/"$deploy_name" \
      -n "$ns" \
      --timeout=180s

    return
  fi

  kubectl get statefulset -n "$ns" --no-headers 2>/dev/null \
    | grep -iq "$svc"

  if [[ $? -eq 0 ]]; then
    sts_name="$(
      kubectl get statefulset -n "$ns" --no-headers \
        | grep -i "$svc" \
        | head -1 \
        | awk '{print $1}'
    )"

    kubectl rollout status statefulset/"$sts_name" \
      -n "$ns" \
      --timeout=180s

    return
  fi

  echo "⚠️ No rollout resource found"
}

########################################
# SYNTHETIC CHECK
########################################
synthetic_test() {
  local svc="$1"

  local path
  local url
  local code

  path="$(get_health_path "$svc")"
  url="https://${svc}.${DOMAIN}${path}"

  echo "Health URL: $url"

  code=$(
    curl -ksS \
      --max-time 5 \
      -o /dev/null \
      -w "%{http_code}" \
      "$url" || echo "000"
  )

  [[ "$code" =~ ^2 ]]
}

########################################
# ARGOCD WAIT
########################################
wait_argocd() {
  local app="$1"

  argocd app wait "$app" \
    --server "$ARGOCD_SERVER" \
    --auth-token "$ARGOCD_AUTH_TOKEN" \
    --grpc-web \
    --sync \
    --health \
    --operation \
    --timeout 180
}

########################################
# VERIFY SERVICE
########################################
verify_service() {
  local svc="$1"

  local stack
  local namespace
  local app
  local base_path
  local url
  local bad
  local percent

  stack="$(get_stack "$svc")"
  namespace="$(get_namespace "$svc")"
  app="$(get_argocd_app "$svc")"

  base_path="$(get_base_path "$svc")"
  url="https://${svc}.${DOMAIN}${base_path}"

  echo
  echo "=================================="
  echo "SERVICE: $svc"
  echo "STACK: $stack"
  echo "NAMESPACE: $namespace"
  echo "ARGOCD APP: $app"
  echo "=================================="

  RESULT["$svc"]="VERIFYING"
  FAIL_REASON["$svc"]=""

  ##################################
  echo "[1/4] ArgoCD sync check..."

  if ! wait_argocd "$app"; then
    RESULT["$svc"]="FAIL"
    FAIL_REASON["$svc"]="ArgoCD failed"
    return
  fi

  ##################################
  echo "[2/4] Rollout validation..."

  if ! check_rollout "$svc" "$namespace"; then
    RESULT["$svc"]="FAIL"
    FAIL_REASON["$svc"]="Rollout failed"
    return
  fi

  ##################################
  echo "[3/4] Pod health..."

  bad="$(check_pods "$svc" "$namespace")"

  if [[ -n "$bad" ]]; then
    echo "$bad"

    RESULT["$svc"]="FAIL"
    FAIL_REASON["$svc"]="Unhealthy pods"
    return
  fi

  ##################################
  # ONLY APP STACKS GET HTTP TESTS
  ##################################
  if [[ "$stack" == "app" ]]; then
    echo "[4/4] Canary + synthetic..."

    percent="$(check_http "$url")"

    echo "Success rate: ${percent}%"

    if (( percent < SUCCESS_THRESHOLD )); then
      RESULT["$svc"]="FAIL"
      FAIL_REASON["$svc"]="Canary failed"
      return
    fi

    if ! synthetic_test "$svc"; then
      RESULT["$svc"]="FAIL"
      FAIL_REASON["$svc"]="Synthetic failed"
      return
    fi
  else
    echo "[4/4] Skipping frontend checks for system stack"
  fi

  RESULT["$svc"]="PASS"

  echo "✅ $svc PASSED"
}

########################################
# MAIN LOOP
########################################
PENDING=("${SERVICES[@]}")

for i in $(seq 1 "$ATTEMPTS"); do
  echo
  echo "=================================="
  echo "CONVERGENCE ITERATION $i/$ATTEMPTS"
  echo "=================================="

  NEXT=()

  for svc in "${PENDING[@]}"; do
    verify_service "$svc"

    if [[ "${RESULT[$svc]}" != "PASS" ]]; then
      NEXT+=("$svc")
    fi
  done

  echo
  echo "PASSED SO FAR:"

  for svc in "${SERVICES[@]}"; do
    [[ "${RESULT[$svc]:-}" == "PASS" ]] && echo "  - $svc"
  done

  echo
  echo "REMAINING:"

  if [[ ${#NEXT[@]} -eq 0 ]]; then
    echo "  - none"
  else
    printf "  - %s\n" "${NEXT[@]}"
  fi

  if [[ ${#NEXT[@]} -eq 0 ]]; then
    break
  fi

  PENDING=("${NEXT[@]}")

  [[ $i -lt "$ATTEMPTS" ]] && sleep "$SLEEP"
done

########################################
# FINAL REPORT
########################################
echo
echo "=================================="
echo "FINAL REPORT"
echo "=================================="

FAIL=0

for svc in "${SERVICES[@]}"; do
  status="${RESULT[$svc]:-UNKNOWN}"
  reason="${FAIL_REASON[$svc]:-}"

  echo "$svc -> $status ($reason)"

  [[ "$status" != "PASS" ]] && FAIL=1
done

echo

if [[ "$FAIL" -eq 1 ]]; then
  echo "❌ SYSTEM NOT STABLE"
  exit 1
else
  echo "✅ SYSTEM VERIFIED"
fi
