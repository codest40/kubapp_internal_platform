#!/usr/bin/env bash
set -euo pipefail

STACK="${1:-infra}"   # infra | k8s
ENV="${2:-dev}"
ACTION="${3:-plan}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_DIR="$ROOT_DIR/iac/$STACK"
ENV_DIR="$BASE_DIR/envs/$ENV"

BACKEND_FILE="$ENV_DIR/backend.hcl"
TFVARS_FILE="$ENV_DIR/${STACK}.tfvars"

echo "=============================="
echo " Terraform Runner"
echo " Stack: $STACK"
echo " Dir: $BASE_DIR"
echo " Environment: $ENV"
echo " Action: $ACTION"
echo "=============================="

# -----------------------------
# VALIDATIONS
# -----------------------------
if [ ! -d "$BASE_DIR" ]; then
  echo "❌ Invalid stack: $STACK (expected infra or k8s)"
  exit 1
fi

if [ ! -d "$ENV_DIR" ]; then
  echo "❌ Environment folder not found: $ENV_DIR"
  exit 1
fi

if [ ! -f "$BACKEND_FILE" ]; then
  echo "❌ Missing backend file: $BACKEND_FILE"
  exit 1
fi

if [ ! -f "$TFVARS_FILE" ]; then
  echo "❌ Missing tfvars file: $TFVARS_FILE"
  exit 1
fi

cd "$BASE_DIR"

# -----------------------------
# INIT
# -----------------------------
echo "=============================="
echo "Initializing Terraform"
echo "=============================="

terraform init -upgrade \
  -backend-config="$BACKEND_FILE"
terraform fmt
terraform validate

# -----------------------------
# ACTION HANDLER
# -----------------------------
case "$ACTION" in

  plan)
    echo "=============================="
    echo "Running plan"
    echo "=============================="
    terraform plan -var-file="$TFVARS_FILE"
    ;;

  apply)
    echo "=============================="
    echo "Running apply"
    echo "=============================="
    terraform apply --auto-approve -var-file="$TFVARS_FILE" -auto-approve
    ;;

  destroy)
    echo "=============================="
    echo "Running destroy"
    echo "=============================="
    terraform destroy --auto-approve -var-file="$TFVARS_FILE"
    ;;

  refresh)
    echo "=============================="
    echo "Running refresh"
    echo "=============================="
    terraform apply -refresh-only -var-file="$TFVARS_FILE"
    ;;

  *)
    echo "❌ Unknown action: $ACTION"
    echo "Allowed: plan | apply | destroy | refresh"
    exit 1
    ;;
esac

echo "=============================="
echo "✅ Done"
echo "=============================="
