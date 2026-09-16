#!/usr/bin/env bash
# runner.sh - Terraform runner (init, fmt, validate, plan, apply, destroy)

set -euo pipefail

ACTION="${1:-apply}"
DIR="${2:-.}"
GITHUB_REPO="${3:-}"

DIRECT="-y"

if [[ "$DIR" != "$DIRECT" ]]; then
  if [[ ! -d "$DIR" ]]; then
    echo "❌ Directory not found: $DIR"
    exit 1
  fi
  cd "$DIR"
fi

run_apply() {
  echo " Running Terraform BACKEND APPLY in: $(pwd)"

  terraform init -reconfigure
  terraform fmt -recursive
  terraform validate
  if [[ -n "$GITHUB_REPO" ]]; then
    if [[ "$GITHUB_REPO" != */* ]]; then
      echo "Invalid GITHUB_REPO: $GITHUB_REPO"
      exit 1
    fi
    REPO_OWNER="${GITHUB_REPO%%/*}"
    REPO_NAME="${GITHUB_REPO#*/}"

    terraform plan \
      -var="github_repository_owner=$REPO_OWNER" \
      -var="github_repository_name=$REPO_NAME"

    terraform apply --auto-approve \
      -var="github_repository_owner=$REPO_OWNER" \
      -var="github_repository_name=$REPO_NAME"
  else
    terraform plan
    terraform apply --auto-approve
  fi

  echo "✅ APPLY complete."
}

run_destroy() {
  echo "⚠️  DESTROYING TFSTATE!!!"
  if [[ "$DIR" != "-y" ]]; then
    read -p "(Dont incure unnecessary cost for yourself) Hope you destroyed that Infra First? (Yes/No): " CONFIRM
    if [[ "${CONFIRM,,}" != "yes" && "${CONFIRM,,}" != "y" ]]; then
      echo "❌ Destroy cancelled Successfully."
      return 1
    fi
  fi

  echo " Running Terraform BACKEND DESTROY in: $(pwd)"

  terraform init -reconfigure
  terraform validate
  terraform plan -destroy
  terraform destroy -var="force_destroy_bucket=true" --auto-approve

  echo "✅ DESTROY complete."
}

case "$ACTION" in
  apply)
    run_apply
    ;;
  destroy)
    run_destroy
    ;;
  *)
    echo "❌ Unknown action: $ACTION"
    echo "Usage:"
    echo "  ./runner.sh apply   [DIR]"
    echo "  ./runner.sh destroy [DIR]"
    exit 1
    ;;
esac

