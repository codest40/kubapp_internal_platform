#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$ROOT_DIR" ]]; then
    echo "[ERROR] Unable to determine project root."
    exit 1
fi
source "$ROOT_DIR/reuse.sh"

BOOT_DIR="$ROOT_DIR/iac/boot"
FUNCTIONS="$ROOT_DIR/setup_functions.sh"
SETUP_ENV_FILE="$ROOT_DIR/setup.env"

source "$FUNCTIONS"

command -v aws >/dev/null 2>&1 || {
  echo "❌ AWS CLI is required."
  exit 1
}

command -v terraform >/dev/null 2>&1 || {
  echo "❌ Terraform is required."
  exit 1
}

command -v gh >/dev/null 2>&1 || {
  echo "❌ GitHub CLI is required."
  exit 1
}

if [[ ! -f "$SETUP_ENV_FILE" ]]; then
  echo "❌ Missing $SETUP_ENV_FILE"
  echo "Create it from the project configuration template."
  exit 1
fi

source "$SETUP_ENV_FILE"

echo "========== AWS =========="

aws sts get-caller-identity

echo
echo "========== GITHUB =========="

gh auth status
discover_repo

echo
echo "========== KUBAPP AWS BOOTSTRAP =========="

"$BOOT_DIR/runner.sh" apply "$BOOT_DIR" "$REPO"

GITHUB_ROLE_ARN="$(terraform -chdir="$BOOT_DIR" output -raw github_actions_role_arn)"
AWS_REGION="$(terraform -chdir="$BOOT_DIR" output -raw region)"

configure_github_variables
configure_github_secrets
configure_github_app

install_infracost
configure_infracost

echo
echo "========== Setting Up Terraform Infra Backends =========="
VAR_SCRIPT="$ROOT_DIR/scripts/supply_tf_vars.sh"
bash "$VAR_SCRIPT"

echo
echo "========== KUBAPP SETUP COMPLETE =========="

echo "Repository: $REPO"
echo "AWS Region: $AWS_REGION"
echo "AWS Role:   $GITHUB_ROLE_ARN"

