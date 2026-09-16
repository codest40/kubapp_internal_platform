#!/usr/bin/env bash

set -euo pipefail

ACTION="${1:-apply}"
PROFILE="${2:-}"
REGION="${3:-}"

if [[ "$ACTION" == "delete" ]]; then
    echo "Try Deleting DNS State itself? run ./bootstrap.sh delete"
    exit 1
fi

run_create() {
  if [[ -z "$PROFILE" ]]; then
    echo "Profile CANNOT Be Empty. Supply it"
    exit 1
  fi

  echo "[RUNNER] Creating Terraform BACKEND: $(pwd)"
  echo "This Action is Usually Once"
  PROFILE=$PROFILE REGION=$REGION ./bootstrap.sh

  echo "[RUNNER] Backend Creation done"
}

run_apply() {
  echo "[RUNNER] Running Terraform APPLY: $(pwd)"

  terraform init -reconfigure -backend-config=backend.hcl
  terraform fmt -recursive
  terraform validate
  terraform plan
  terraform apply --auto-approve

  echo "✅ APPLY complete."
}

run_destroy() {
  echo "⚠️ DESTROYING TFSTATE!!!"

  read -p "(Dont incur unnecessary cost for yourself) Hope you destroyed that Infra First? (Yes/No): " CONFIRM
  CONFIRM="${CONFIRM,,}"

  if [[ "$CONFIRM" != "yes" && "$CONFIRM" != "y" ]]; then
    echo "❌ Destroy cancelled successfully."
    return 1
  fi

  echo "[RUNNER] Running Terraform DESTROY: $(pwd)"

  terraform init -reconfigure -backend-config=backend.hcl
  terraform validate
  terraform plan -destroy
  terraform destroy \
  #  -var="force_destroy_bucket=true" \
    --auto-approve

  echo "✅ DESTROY complete."
}

case "$ACTION" in
  create)
    run_create
    ;;
  apply)
    run_apply
    ;;
  destroy)
    run_destroy
    ;;
  *)
    echo "❌ Unknown action: $ACTION"
    echo "Usage:"
    echo "  ./runner.sh create PROFILE=<profile> REGION=<region>"
    echo "  ./runner.sh apply"
    echo "  ./runner.sh destroy"
    exit 1
    ;;
esac
