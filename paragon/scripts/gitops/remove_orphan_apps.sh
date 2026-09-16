#!/usr/bin/env bash

set -euo pipefail

ENV="${ENV:-dev}"
SERVICES="${SERVICES:-}"
ING_FILE="${INGRESS_FILE:-gitops/ingress/${ENV}/values.yaml}"
APP_BASE="${APP_DIR:-gitops/envs/${ENV}/apps}"

if [[ ! -f "$ING_FILE" ]]; then
  echo "❌ Ingress file not found: $ING_FILE"
  exit 1
fi

echo "=============================="
echo " ORPHAN APP CLEANUP ENGINE"
echo " ENV: $ENV"
echo "=============================="

VALID_APPS=$(yq '.services[].name' "$ING_FILE")

echo
echo "Valid apps:"
echo "$VALID_APPS"
echo

if [[ -n "$SERVICES" ]]; then

  echo "MODE: manual"

  SERVICES=$(echo "$SERVICES" | tr ',' ' ' | xargs -n1 | sort -u)

  for app in $SERVICES; do

    APP_PATH="$APP_BASE/$app"

    echo
    echo "Checking manual delete: $app"

    if [[ ! -d "$APP_PATH" ]]; then
      echo "SKIP: not found $APP_PATH"
      continue
    fi

    APP_NAME="$(basename "$APP_PATH")"

    if [[ "$APP_NAME" == *_* ]]; then
      APP_NAME="${APP_NAME//_/-}"
    fi

    if echo "$VALID_APPS" | grep -qx "$APP_NAME"; then
      echo "BLOCKED: $app exists in ingress"
      continue
    fi

    if [[ "$ENV" == "prod" ]]; then
      echo "BLOCKED: prod manual delete"
      continue
    fi

    echo "Deleting: $APP_PATH"
    rm -rf "$APP_PATH"

  done

  exit 0
fi

echo "MODE: auto"

if [[ ! -d "$APP_BASE" ]]; then
  echo "No app directory: $APP_BASE"
  exit 0
fi

for APP_PATH in "$APP_BASE"/*; do

  [[ -d "$APP_PATH" ]] || continue

  ORIGINAL_APP_NAME="$(basename "$APP_PATH")"

  if [[ ! -f "$APP_PATH/values.yaml" ]]; then
    continue
  fi

  APP_NAME="$ORIGINAL_APP_NAME"

  if [[ "$APP_NAME" == *_* ]]; then
    APP_NAME="${APP_NAME//_/-}"
  fi

  if echo "$VALID_APPS" | grep -qx "$APP_NAME"; then
    echo "KEEP: $ORIGINAL_APP_NAME"
    continue
  fi

  echo "ORPHAN: $ORIGINAL_APP_NAME"

  if [[ "$ENV" == "prod" ]]; then
    echo "BLOCKED: prod delete"
    continue
  fi

  echo "Deleting: $APP_PATH"
  rm -rf "$APP_PATH"

done

echo
echo "=============================="
echo "✅ Orphan reconciliation complete."
echo "=============================="
