#!/usr/bin/env bash
set -euo pipefail

WORKDIR="${1:-.}"
cd "$WORKDIR"

echo " STATE vs CLOUD MISMATCH CHECK"
echo "--------------------------------"

terraform init -input=false >/dev/null

echo ""
echo " Running pre-refresh plan (this is the real comparison)"
echo "--------------------------------"

set +e
terraform plan -detailed-exitcode -no-color -out=tf.plan
EXIT_CODE=$?
set -e

echo ""
echo "--------------------------------"

if [[ $EXIT_CODE -eq 0 ]]; then
  echo "✅ RESULT: STATE MATCHES CLOUD"
  exit 0

elif [[ $EXIT_CODE -eq 2 ]]; then
  echo "⚠️ RESULT: STATE DOES NOT MATCH CLOUD"

  echo ""
  echo " Drift details:"
  terraform show tf.plan

  echo ""
  echo " Saving machine-readable diff..."
  terraform show -json tf.plan > drift.json || true

  echo ""
  echo "Meaning:"
  echo "   Terraform state is outdated compared to real AWS infrastructure"
  echo "   OR AWS resources changed outside Terraform"

  exit 2

else
  echo "❌ ERROR: Terraform failed"
  exit 1
fi
