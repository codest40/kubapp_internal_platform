#!/usr/bin/env bash
set -euo pipefail

SERVICE=$1
ENV=$2
IMAGE_TAG=$3

APP_FILE="gitops/infra/apps/${SERVICE}-${ENV}.yml"

echo "Promoting $SERVICE to $ENV with image tag: $IMAGE_TAG"

if [ ! -f "$APP_FILE" ]; then
  echo "❌ App not found: $APP_FILE"
  exit 1
fi

# Update Helm image tag inside ArgoCD app
yq e ".spec.source.helm.values.image.tag = \"$IMAGE_TAG\"" -i "$APP_FILE"

echo "✅ Updated ArgoCD app: $APP_FILE"

echo "Next step: sync app"
echo "argocd app sync ${SERVICE}-${ENV}"
