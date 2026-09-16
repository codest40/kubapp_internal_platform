#!/bin/bash
set -euo pipefail

DEBUG="${DEBUG:-0}"
REPO_URL="${REPO_URL:-}"

if [[ -z "$REPO_URL" ]]; then
    echo "REPO URL: https://github.com/${GITHUB_REPOSITORY}.git is Required"
    exit 1
fi

log() {
  echo "========================================"
  echo "$1"
  echo "========================================"
}

run() {
  echo ""
  echo "➜ RUNNING: $*"
  if [[ "$DEBUG" == "1" ]]; then
    "$@" 2>&1 | tee /tmp/kubectl-debug.log
  else
    "$@"
  fi
}

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"

if [[ -z "$ROOT" || "$ROOT" == "null" ]]; then
    ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

APPSET_FILE="$ROOT/gitops/argocd/appset.yaml"
INGRESS_FILE="$ROOT/gitops/argocd/ingress.yaml"

APPSET_RENDERED="/tmp/kubapp-appset.yaml"
INGRESS_RENDERED="/tmp/kubapp-ingress.yaml"

export REPO_URL

log "GitOps Bootstrap Starting..."
echo "ROOT: $ROOT"
echo "REPO_URL: $REPO_URL"

envsubst '${REPO_URL}' < "$APPSET_FILE" > "$APPSET_RENDERED"
envsubst '${REPO_URL}' < "$INGRESS_FILE" > "$INGRESS_RENDERED"

echo ""
echo "========================================"
echo " RENDERED APPSET"
echo "========================================"
cat "$APPSET_RENDERED"

echo ""
echo "========================================"
echo " RENDERED INGRESS"
echo "========================================"
cat "$INGRESS_RENDERED"

echo ""
log "APPLYING ARGOCD APPSET"
run kubectl apply -n argocd -f "$APPSET_RENDERED" -v=8

echo ""
log "APPLYING ARGOCD INGRESS"
run kubectl apply -n argocd -f "$INGRESS_RENDERED" -v=8

echo ""
log "POST APPLY STATE (ARGOCD PODS)"
run kubectl get pods -n argocd -o wide

echo ""
log "ARGOCD APPLICATIONS (CRITICAL DEBUG STEP)"
run kubectl get applications -n argocd || true
run kubectl get applicationsets -n argocd -o wide || true

echo ""
log "CLUSTER STATE CHECK (dev namespace)"
run kubectl get pods -n dev -o wide || true
run kubectl get deploy -n dev || true
run kubectl get svc -n dev || true

echo ""
log "GitOps Bootstrap Complete"
