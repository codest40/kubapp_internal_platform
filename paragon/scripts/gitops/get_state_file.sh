#!/usr/bin/env bash
set -euo pipefail

STATE_FILE="gitops/state/current.json"

if [[ ! -f "$STATE_FILE" || ! -s "$STATE_FILE" ]]; then
  echo "❌ State File: $STATE_FILE is Missing or Empty. Cannot Decipher the appropriate ENV to update"
  exit 1
fi

CURRENT_RUN_ID="${{ github.event.workflow_run.id }}"
STATE_RUN_ID=$(jq -r '.run_id' "$STATE_FILE")
STATE_TS=$(jq -r '.timestamp' "$STATE_FILE")

if [[ "$STATE_RUN_ID" != "$CURRENT_RUN_ID" ]]; then
  echo "⚠️ State file is stale or from another run"
  echo "State: $STATE_RUN_ID | Current: $CURRENT_RUN_ID"
  exit 1
fi

MAX_AGE=18000
NOW_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
STATE_EPOCH=$(date -d "$STATE_TS" +%s)
NOW_EPOCH=$(date -d "$NOW_TS" +%s)

echo "State Timestamp: $STATE_TS"
echo "Now Timestamp  : $NOW_TS"

AGE=$((NOW_EPOCH - STATE_EPOCH))

if (( AGE > MAX_AGE )); then
  echo "❌ State file too old ($AGE sec)"
  exit 1
fi

STATE_ENV=$(jq -r '.env' "$STATE_FILE")

if [[ -z "$STATE_ENV" || "$STATE_ENV" == "null" ]]; then
  echo "❌ ENV Source from state file Empty"
  exit 1
fi

echo "Detected ENV: $STATE_ENV"

# -----------------------------
# CI vs LOCAL behavior
# -----------------------------
if [[ "${GITHUB_ACTIONS:-}" == "true" || "${CI:-}" == "true" ]]; then
  echo "Running in CI → exporting to GITHUB_ENV"
  echo "ENV=$STATE_ENV" >> "$GITHUB_ENV"
else
  echo "Running locally → not exporting to CI env"
  export ENV="$STATE_ENV"
fi
