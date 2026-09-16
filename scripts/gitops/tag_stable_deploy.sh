#!/usr/bin/env bash
set -euo pipefail

ENV="${{ env.ENV }}"
services "$(find gitops/registry/$ENV -name '*.json' | wc -l)"
COMMIT="$(git rev-parse HEAD)"
TIME="$(date +%Y-%m-%d_%H:%M:%S)"
DIR="snapshot/deploys"
file="$DIR/${TIME}.json"

mkdir -p "$DIR"

jq -n \
  --arg env "$ENV" \
  --arg commit "$COMMIT" \
  --arg time "$TIME" \
  --arg services "$services"  \
  '{
    env: $env,
    commit: $commit,
    time: $time,
    service_count: $services
  }'

echo "✅ Snapshot created"
cat $file

