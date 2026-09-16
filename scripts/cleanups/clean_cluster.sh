#!/usr/bin/env bash
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
TF_CREATED_NS_JSON=${TF_CREATED_NS:-[]}

mapfile -t TF_CREATED_NS < <(
  printf '%s' "$TF_CREATED_NS_JSON" | jq -r '.[] | strings'
)

echo "======================================"
echo "  KUBERNETES RECONCILIATION CLEANER"
echo "======================================"

# SAFETY GUARD
CTX=$(kubectl config current-context || true)
if echo "$CTX" | grep -qi "prod"; then
  echo "❌ Refusing to run in prod context: $CTX"
  exit 1
fi


sleep_safe() { sleep "${1:-3}"; }

count_resources() {
  kubectl get "$1" -n "$2" --no-headers 2>/dev/null | wc -l || true
}

patch_finalizers_ns() {
  local ns=$1
  echo ">> Removing namespace finalizers: $ns"
  kubectl patch ns "$ns" -p '{"spec":{"finalizers":[]}}' --type=merge >/dev/null 2>&1 || true
}

patch_finalizers_objects() {
  local ns=$1
  local type=$2

  for obj in $(kubectl get "$type" -n "$ns" -o name 2>/dev/null || true); do
    kubectl patch "$obj" -n "$ns" \
      -p '{"metadata":{"finalizers":[]}}' --type=merge >/dev/null 2>&1 || true
  done
}

# SAFE FORCE DELETE
nuke_as_last_option() {
  local ns="$1"
  local type="$2"

  echo "🔥 NUCLEAR MISSILE MODE Finally: $type in $ns"

  for obj in $(kubectl get "$type" -n "$ns" -o name 2>/dev/null || true); do
    echo "   → force deleting $obj"
    kubectl delete "$obj" -n "$ns" \
      --grace-period=0 --force --ignore-not-found || true
  done
}

safe_delete_loop() {
  local ns=$1
  local type=$2
  local timeout=${3:-40}

  echo ">> Cleaning $type in $ns"

  SECONDS=0

  while true; do

    kubectl delete "$type" -n "$ns" --all --ignore-not-found >/dev/null 2>&1 || true
    sleep_safe 3

    remaining=$(count_resources "$type" "$ns")

    if [[ "$remaining" -eq 0 ]]; then
      echo "✅ $type cleaned in $ns"
      return 0
    fi

    echo "⚠️ $type remaining: $remaining"

    if (( SECONDS > timeout )); then

      echo "⛔ TIMEOUT reached for $type in $ns"

      echo ">> Step 1: Inspect"
      kubectl get "$type" -n "$ns" || true

      echo ">> Step 2: Remove finalizers"
      patch_finalizers_objects "$ns" "$type"

      sleep_safe 3

      remaining=$(count_resources "$type" "$ns")

      if [[ "$remaining" -gt 0 ]]; then
        echo "Step 3: FORCE NUKE triggered"
        nuke_as_last_option "$ns" "$type"
      fi

      SECONDS=0
    fi

    sleep_safe 5
  done
}

# ARGOCD HARD STOp
echo ">> STOPPING ArgoCD RECONCILIATION FIRST"

kubectl delete applicationsets.argoproj.io --all -n argocd --ignore-not-found || true
kubectl delete applications.argoproj.io --all -n argocd --ignore-not-found || true

#Idea: kill finalizers if stuck apps remain
for app in $(kubectl get applications.argoproj.io -n argocd -o name 2>/dev/null || true); do
  kubectl patch "$app" -n argocd \
    -p '{"metadata":{"finalizers":[]}}' --type=merge || true
done

ALL_NS=$(kubectl get ns -o jsonpath='{.items[*].metadata.name}')

for ns in $ALL_NS; do

  case "$ns" in
    kube-system|default|kube-public|kube-node-lease|argocd)
      echo "Skipping system namespace: $ns"
      continue
      ;;
  esac

  echo ""
  echo "=============================="
  echo " CLEANING: $ns"
  echo "=============================="

  safe_delete_loop "$ns" "applications.argoproj.io" 30
  safe_delete_loop "$ns" "ingress" 40
  safe_delete_loop "$ns" "all" 50
  safe_delete_loop "$ns" "svc" 30
  safe_delete_loop "$ns" "pvc" 60
  safe_delete_loop "$ns" "secret" 30

  # TF SAFE SKIP
  for tf_ns in "${TF_CREATED_NS[@]}"; do
    if [[ "$ns" == "$tf_ns" ]]; then
      echo "Skipping Terraform-managed namespace: $ns"
      continue 2
    fi
  done

  echo ">> Deleting namespace: $ns"

  SECONDS=0
  kubectl delete ns "$ns" --ignore-not-found || true

  while kubectl get ns "$ns" >/dev/null 2>&1; do

    status=$(kubectl get ns "$ns" -o jsonpath='{.status.phase}' 2>/dev/null || true)

    echo "⚠️ $ns still exists ($status)"

    if [[ "$status" == "Terminating" ]]; then
      patch_finalizers_ns "$ns"
    fi

    if (( SECONDS > 60 )); then
      echo " FINAL NUKE OF NAMESPACE"

      kubectl get all -n "$ns" -o name | xargs -r kubectl delete -n "$ns" --force --grace-period=0 || true
      patch_finalizers_ns "$ns" || true
      break
    fi

    sleep_safe 5
  done

  echo "✅ Done: $ns"

done

echo ""
echo ">> Remaining ingress:"
kubectl get ingress -A || true

echo ""
echo ">> Remaining namespaces:"
kubectl get ns

echo ""
echo "======================================"
echo " CLEANUP COMPLETE !!"
echo "======================================"

