#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"

if [[ -z "$ROOT_DIR" ]]; then
  ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

APP_NAME="KUBAPP"
APP_DESCRIPTION="KUBAPP platform automation"

command -v gh >/dev/null 2>&1 || {
  echo "❌ GitHub CLI is required."
  exit 1
}

command -v curl >/dev/null 2>&1 || {
  echo "❌ curl is required."
  exit 1
}

command -v python3 >/dev/null 2>&1 || {
  echo "❌ python3 is required."
  exit 1
}

discover_repo() {
  local remote_url repo_path

  remote_url="$(git -C "$ROOT_DIR" remote get-url origin 2>/dev/null || true)"

  if [[ -z "$remote_url" ]]; then
    echo "❌ Could not determine the GitHub repository from origin."
    exit 1
  fi

  case "$remote_url" in
    https://github.com/*)
      repo_path="${remote_url#https://github.com/}"
      ;;
    git@github.com:*)
      repo_path="${remote_url#git@github.com:}"
      ;;
    git-*:*/*)
      repo_path="${remote_url#*:}"
      ;;
    *)
      echo "❌ Unsupported GitHub remote format: $remote_url"
      exit 1
      ;;
  esac

  repo_path="${repo_path%.git}"

  REPO="$(gh repo view "$repo_path" --json nameWithOwner --jq '.nameWithOwner')"
  REPO_URL="$(gh repo view "$repo_path" --json url --jq '.url')"

  echo "Repository: $REPO"
  echo "URL:        $REPO_URL"
}

secret_exists() {
  local name="$1"

  gh secret list \
    --repo "$REPO" \
    --json name \
    --jq '.[].name' |
    grep -Fxq "$name"
}

store_secret() {
  local name="$1"
  local value="$2"

  if secret_exists "$name"; then
    echo "✓ $name already exists"
    return
  fi

  gh secret set "$name" \
    --repo "$REPO" \
    --body "$value"

  echo "✓ $name created"
}

check_existing_app() {
  local app_id=false
  local private_key=false
  local installation=false

  secret_exists "APP_ID_GITHUB" && app_id=true
  secret_exists "APP_PRIVATE_KEY_GITHUB" && private_key=true
  secret_exists "INSTALLATION_ID" && installation=true

  if [[ "$app_id" == true &&
        "$private_key" == true &&
        "$installation" == true ]]; then
    echo
    echo "✓ KUBAPP GitHub App is already configured."
    return 0
  fi

  return 1
}

create_manifest() {
  local manifest_file

  manifest_file="$(mktemp)"

  cat > "$manifest_file" <<EOF
{
  "name": "$APP_NAME",
  "description": "$APP_DESCRIPTION",
  "public": false,
  "default_permissions": {
    "metadata": "read",
    "actions": "write",
    "contents": "write",
    "pull_requests": "write"
  }
}
EOF

  echo "$manifest_file"
}

register_app() {
  local manifest_file encoded_manifest registration_url

  manifest_file="$(create_manifest)"

  encoded_manifest="$(
    python3 - "$manifest_file" <<'PY'
import json
import sys
import urllib.parse

with open(sys.argv[1], "r", encoding="utf-8") as f:
    manifest = json.load(f)

print(urllib.parse.quote(json.dumps(manifest, separators=(",", ":"))))
PY
  )"

  rm -f "$manifest_file"

  registration_url="https://github.com/settings/apps/new?state=kubapp&manifest=$encoded_manifest"

  echo
  echo "========== GITHUB APP REGISTRATION =========="
  echo
  echo "A GitHub App is required for this account."
  echo
  echo "Open this URL in your browser:"
  echo
  echo "$registration_url"
  echo
  echo "Create the KUBAPP GitHub App from GitHub."
  echo
  echo "After creation, GitHub will provide the App credentials."
  echo
  echo "This script will continue after the App has been created."
}

main() {
  echo "========== KUBAPP GITHUB APP SETUP =========="

  gh auth status

  echo
  discover_repo

  echo

  if check_existing_app; then
    exit 0
  fi

  register_app

  echo
  echo "⚠️ GitHub App registration is not yet automated beyond the"
  echo "   GitHub Manifest registration step."
  echo
  echo "After creating the App, rerun:"
  echo
  echo "  $0"
  echo
  echo "The next stage will capture the App credentials and"
  echo "install the App on the repository."
}

main "$@"
