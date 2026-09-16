#!/usr/bin/env bash
set -euo pipefail

ENV="${ENV:?ENV required}"
PROJECT="${PROJECT:-kubapp}"
REGION="${AWS_REGION:-us-east-1}"

echo "========================================"
echo "CloudWatch orphan log cleanup"
echo "ENV     = $ENV"
echo "PROJECT = $PROJECT"
echo "REGION  = $REGION"
echo "========================================"

# safety gate
if [[ "$ENV" == "prod" || "$ENV" == "production" ]]; then
  echo "❌ Refusing to run in prod"
  exit 1
fi

########################################
# STEP 1: GET ALL LOG GROUPS FOR PROJECT
########################################

echo "Fetching candidate log groups..."

CANDIDATES=$(aws logs describe-log-groups \
  --region "$REGION" \
  --query "logGroups[?contains(logGroupName, \`$PROJECT-$ENV\`)].logGroupName" \
  --output text)

########################################
# STEP 2: FILTER ONLY ORPHANS
########################################
if [[ -z "$CANDIDATES" ]]; then
  echo "No Log Group Found"
  exit 0
fi

for lg in $CANDIDATES; do

  RETENTION=$(aws logs describe-log-groups \
    --region "$REGION" \
    --log-group-name-prefix "$lg" \
    --query "logGroups[0].retentionInDays" \
    --output text 2>/dev/null || echo "unknown")

  # skip Terraform-managed style logs (safety guard)
  if [[ "$lg" == *"terraform"* ]]; then
    echo "Skipping Terraform-managed log: $lg"
    continue
  fi

  # never-expiring logs ONLY
  if [[ "$RETENTION" != "None" && "$RETENTION" != "never-expiring" && "$RETENTION" != "infinite" ]]; then
    echo "Skipping retained log group: $lg (retention=$RETENTION)"
    continue
  fi

  echo "Deleting orphan log group: $lg"

  aws logs delete-log-group \
    --region "$REGION" \
    --log-group-name "$lg" || true

done

echo "========================================"
echo "✅ Log cleanup completed safely"
echo "========================================"
