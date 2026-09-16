#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"

if [[ -z "$ROOT" ]]; then
    ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
fi

echo "ROOT: $ROOT"
echo "Running Prechecks..."

kubectl cluster-info >/dev/null || {
    echo "❌ Cluster unreachable"
    exit 1
}

kubectl get ns argocd >/dev/null || {
    echo "❌ ArgoCD not installed"
    exit 1
}

test -f "$ROOT/gitops/argocd/appset.yaml" || {
    echo "❌ AppSet missing: $ROOT/gitops/argocd/appset.yaml"
    exit 1
}

test -f "$ROOT/gitops/argocd/ingress.yaml" || {
    echo "❌ Ingress missing: $ROOT/gitops/argocd/ingress.yaml"
    exit 1
}

echo "✅ Prechecks passed"
