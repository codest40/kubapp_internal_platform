#!/usr/bin/env bash
# runner.sh - Terraform runner (init, fmt, validate, plan, apply, destroy)

set -euo pipefail

ACTION="${1:-apply}"   # default action = apply
DIR="${2:-.}"          # default directory = current folder
MODE="{MODE:-default}"

if [[ ! -d "$DIR" ]]; then
  echo "❌ Directory not found: $DIR"
  exit 1
fi

cd "$DIR"

run_apply() {
  echo " Running Terraform BACKEND APPLY in: $(pwd)"

  terraform init -reconfigure
  terraform fmt -recursive
  terraform validate
  terraform plan
  terraform apply --auto-approve

  echo "✅ APPLY complete."
}

run_destroy() {
  if [[ "$MODE" == "default" ]]; then
    read -p "⚠️  DESTROY this TFSTATE, Hope you destroyed the Infra First? (yes/no): " CONFIRM
    if [[ "$CONFIRM" != "yes" ]]; then
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

