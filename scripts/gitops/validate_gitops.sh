#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$ROOT_DIR" ]]; then
    echo "[ERROR] Unable to determine project root."
    exit 1
fi
source "$ROOT_DIR/reuse.sh"

echo
echo "=================================================="
echo "[INFO] GITOPS VALIDATION STARTED"
echo "=================================================="
echo

# DIRECTORIES
DIRS=(
  "gitops/argocd"
  "gitops/envs"
  "gitops/ingress"
  "gitops/charts"
  "gitops/state"
  "gitops/registry"

)

############################################
# HELPERS
############################################
fail() {
  echo
  echo "[ERROR] ❌ $1"
  echo "=================================================="
  exit 1
}

check_dir() {
  [[ -d "$1" ]] || fail "Missing directory: $1"
}

check_yaml() {
  local file="$1"
  yq e '.' "$file" >/dev/null 2>&1 || fail "Invalid YAML: $file"
}

############################################
# PREREQUISITES
############################################
echo "--------------------------------------------------"
echo "[INFO] CHECKING PREREQUISITES"
echo "--------------------------------------------------"

if ! command -v yq >/dev/null 2>&1; then
  fail "yq is required but not installed"
fi

echo "[INFO] ✅ yq available"
echo

############################################
# VALIDATE CORE STRUCTURE
############################################
echo "--------------------------------------------------"
echo "[INFO] CORE STRUCTURE VALIDATION"
echo "--------------------------------------------------"

for dir in "${ROOT/DIRS[@]}"; do
  echo
  echo "[INFO] Checking directory: $dir"

  check_dir "$dir"

  mapfile -t FILES < <(
    find "$dir" \( -name "*.yml" -o -name "*.yaml" \)
  )

  if [[ ${#FILES[@]} -eq 0 ]]; then
    echo "[WARN] ⚠️ No YAML files found in $dir"
    continue
  fi

  ############################################
  # FILE VALIDATION LOOP
  ############################################
  for file in "${FILES[@]}"; do
    echo "[INFO] Validating file: $file"

    # basic YAML check
    if [[ "$file" == *"/templates/"* ]]; then
      echo "[INFO] Skipping raw YAML validation for Helm template"
    else
      check_yaml "$file"
    fi

    ############################################
    # ARGOCD VALIDATION
    ############################################
    if [[ "$dir" == "gitops/argocd" ]]; then
      KIND=$(yq e '.kind' "$file")
      NAME=$(yq e '.metadata.name' "$file")

      [[ "$NAME" != "null" && -n "$NAME" ]] || fail "Missing metadata.name in $file"

      if [[ "$KIND" == "ApplicationSet" || "$KIND" == "Application" ]]; then
        echo "[INFO] ✅ ArgoCD object valid: $KIND ($NAME)"
      else
        fail "Invalid ArgoCD kind in $file: $KIND"
      fi
    fi

    ############################################
    # ENV VALIDATION (values.yaml)
    ############################################
    if [[ "$dir" == "gitops/envs" ]]; then
      if [[ "$file" == *"/apps/"* ]]; then
        APP_NAME=$(yq e '.appName' "$file")
        NAMESPACE=$(yq e '.namespace' "$file")
        IMAGE=$(yq e '.image.repository' "$file")

        [[ -n "$APP_NAME" && "$APP_NAME" != "null" ]] || fail "Missing appName in $file"
        [[ -n "$NAMESPACE" && "$NAMESPACE" != "null" ]] || fail "Missing namespace in $file"
        [[ -n "$IMAGE" && "$IMAGE" != "null" ]] || fail "Missing image.repository in $file"

        echo "[INFO] ✅ App env config valid: $APP_NAME ($NAMESPACE)"
      fi
      if [[ "$file" == *"/backend_proxy/"* ]]; then
        NAME=$(yq e '.metadata.name' "$file")
        NS=$(yq e '.metadata.namespace' "$file")
        [[ -n "$NAME" && "$NAME" != "null" ]] || fail "Missing appName in backend_proxy: $file"
        [[ -n "$NS" && "$NS" != "null" ]] || fail "Missing namespace in $file"

        echo "[INFO] ✅ Backend proxy valid: $NAME with $NS"
      fi
    fi
    ############################################
    # INGRESS VALIDATION
    ############################################
    if [[ "$dir" == "gitops/ingress" ]]; then
      INGRESS_NAME=$(yq e '.ingress.name' "$file")
      SERVICES_COUNT=$(yq e '.services | length' "$file")

      [[ -n "$INGRESS_NAME" && "$INGRESS_NAME" != "null" ]] || fail "Missing ingress.name in $file"
      [[ "$SERVICES_COUNT" -ge 0 ]] || fail "Invalid services list in $file"

      echo "[INFO] ✅ Ingress valid: $INGRESS_NAME (services: $SERVICES_COUNT)"
    fi
  done
done

############################################
# HELM VALIDATION
############################################
echo
echo "--------------------------------------------------"
echo "[INFO] HELM CHART VALIDATION"
echo "--------------------------------------------------"

if command -v helm >/dev/null 2>&1; then
  echo "[INFO] Helm detected, validating charts..."

  for chart in gitops/charts/*; do
    [[ -d "$chart" ]] || continue

    if [[ -f "$chart/Chart.yaml" ]]; then
      echo "[INFO] Checking Helm chart: $chart"

      if ! OUTPUT=$(helm template test "$chart" 2>&1); then
        echo "[ERROR] ❌ Helm template validation failed: $chart"
        echo "---------------- DEBUG OUTPUT ----------------"
        echo "$OUTPUT"
        echo "---------------------------------------------"
        exit 1
      fi
      #helm template test "$chart" || fail "Helm template validation failed: $chart"

      echo "[INFO] ✅ Helm chart valid: $chart"
    fi
  done

else
  if [[ "${CI:-}" == "true" ]]; then
    fail "helm is required in CI but not installed"
  else
    echo "[WARN] ⚠️ Helm not installed locally — skipping Helm chart validation"
  fi
fi

############################################
# DONE
############################################
echo
echo "=================================================="
echo "[INFO] ✅ FULL GITOPS VALIDATION SUCCESSFUL"
echo "=================================================="
echo
