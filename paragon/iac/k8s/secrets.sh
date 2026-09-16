#!/usr/bin/env bash

set -euo pipefail
SECRET_FILE="${1:-}"

if [[ -z "$SECRET_FILE" || ! -f "$SECRET_FILE" ]]; then
  echo "[GRAFANA SECRET] Secret file path not provided, constructing it..."
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"
  if [[ -z "$ROOT" ]]; then
    ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
  fi

  SECRET_FILE="$ROOT/gitops/secrets/grafana-secret.yaml"
  if [[ ! -f "$SECRET_FILE" ]]; then
    echo "❌ Secret file not found: $SECRET_FILE"
    exit 1
  fi
fi

command -v sops >/dev/null 2>&1 || {
  echo "❌ sops is not installed"
  exit 1
}

command -v kubectl >/dev/null 2>&1 || {
  echo "❌ kubectl is not installed"
  exit 1
}

echo "Using SOPS secret:"
echo "$SECRET_FILE"
echo "Applying Grafana admin secret..."
sops -d "$SECRET_FILE" | kubectl apply -f -
echo "✅ Grafana admin secret provisioned"
