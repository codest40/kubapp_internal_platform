#!/bin/bash
set -euo pipefail

echo "Setting up ArgoCD GitHub App integration + cluster observability"

# =========================
# Required env vars
# =========================
: "${APP_ID:?Missing APP_ID}"
: "${PRIVATE_KEY_FILE:?Missing PRIVATE_KEY_FILE}"
: "${INSTALLATION_ID:?Missing INSTALLATION_ID}"
: "${REPO_URL:?Missing REPO_URL}"

echo "Generating GitHub App installation token..."

# NOTE: Proper GitHub App auth flow requires JWT + installation token
JWT_HEADER=$(python3 - <<EOF
import jwt, time
with open("$PRIVATE_KEY_FILE") as f:
    private_key = f.read()

payload = {
    "iat": int(time.time()),
    "exp": int(time.time()) + 600,
    "iss": int($APP_ID)
}

print(jwt.encode(payload, private_key, algorithm="RS256"))
EOF
)

TOKEN=$(curl -s -X POST \
  -H "Authorization: Bearer $JWT_HEADER" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/app/installations/$INSTALLATION_ID/access_tokens" \
  | jq -r .token)

if [[ -z "$TOKEN" || "$TOKEN" == "null" ]]; then
  echo "❌ Failed to generate GitHub App token"
  exit 1
fi

echo "✅ GitHub App token generated"

echo " Registering repo in ArgoCD..."

argocd repo add "$REPO_URL" \
  --username x-access-token \
  --password "$TOKEN"

echo "✅ Repo linked to ArgoCD"

# =========================
# Metrics Server Install
# =========================

echo "Installing Metrics Server..."

kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

echo " Waiting for metrics-server rollout..."
kubectl -n kube-system rollout status deployment metrics-server || true

echo " Patching metrics-server for EKS compatibility..."

kubectl -n kube-system patch deployment metrics-server \
  --type='json' \
  -p='[
    {"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"},
    {"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-preferred-address-types=InternalIP"}
  ]'

echo " Done"
echo "Now verify:"
echo "  kubectl top nodes"
echo "  kubectl top pods -n dev"
