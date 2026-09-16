#!/usr/bin/env bash
set -euo pipefail

SYNC_MODE="${SYNC_MODE:-apply}"
DOMAIN="${DOMAIN:-rundailytest.online}"
ENV="${ENV:-dev}"
ZONE_ID="${ZONE_ID:?ZONE_ID is required}"

ING_FILE="${INGRESS_FILE:-gitops/ingress/$ENV/values.yaml}"
MON_FILE="${MON_FILE:-gitops/ingress/$ENV/monitoring.yaml}"
ARGO_FILE="${ARGO_FILE:-gitops/ingress/$ENV/argocd.yaml}"
AWS_REGION="${AWS_REGION:-$(aws configure get region)}"

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$ROOT" ]]; then
    echo "[ERROR] Unable to determine project root."
    return 1 2>/dev/null || exit 1
fi

echo "===================================="
echo "Route53 DNS Sync"
echo "SYNC_MODE:  $SYNC_MODE"
echo "DOMAIN:     $DOMAIN"
echo "ZONE_ID:    $ZONE_ID"
echo "ENV:        $ENV"
echo "AWS_REGION: $AWS_REGION"
echo "===================================="
ING_FILE="$ROOT/$ING_FILE"
MON_FILE="$ROOT/$MON_FILE"
ARGO_FILE="$ROOT/$ARGO_FILE"

for file in "$ING_FILE" "$MON_FILE" "$ARGO_FILE"; do
  if [[ ! -f "$file" ]]; then
    echo "❌ File not found: $file"
    exit 1
  fi
done

APP_SERVICES=$(yq e '.services[].name' "$ING_FILE" 2>/dev/null || true)
MON_SERVICES=$(yq e '.services[].name' "$MON_FILE" 2>/dev/null || true)
ARGO_SERVICES=$(yq e '.services[].name' "$ARGO_FILE" 2>/dev/null || true)

ALL_SERVICES=$(
  printf "%s\n%s\n%s\n" \
    "$APP_SERVICES" \
    "$MON_SERVICES" \
    "$ARGO_SERVICES" |
    grep -v '^$' |
    sort -u
)

mapfile -t SERVICES <<< "$ALL_SERVICES"

echo "Services:"
printf ' - %s\n' "${SERVICES[@]}"

if [[ "$SYNC_MODE" == "destroy" ]]; then
  echo "===================================="
  echo "DESTROY MODE"
  echo "===================================="

  EXISTING=$(aws route53 list-resource-record-sets \
    --hosted-zone-id "$ZONE_ID")

  for svc in "${SERVICES[@]}"; do
    FQDN="${svc}.${DOMAIN}."

    echo "Removing: $FQDN"

    RECORDS=$(echo "$EXISTING" | jq -c \
      --arg fqdn "$FQDN" \
      '.ResourceRecordSets[]
      | select(.Name == $fqdn)
      | select(.Type == "A" or .Type == "AAAA" or .Type == "CNAME")')

    if [[ -n "$RECORDS" ]]; then
      while read -r record; do
        aws route53 change-resource-record-sets \
          --hosted-zone-id "$ZONE_ID" \
          --change-batch "{
            \"Changes\": [{
              \"Action\": \"DELETE\",
              \"ResourceRecordSet\": $record
            }]
          }"
      done <<< "$RECORDS"

      echo "✅ Deleted: $FQDN"
    else
      echo "⚠ Not found: $FQDN"
    fi
  done

  echo "===================================="
  echo "DNS DESTROY COMPLETE"
  echo "===================================="

  exit 0
fi


echo "Fetching ALB..."
ALB_ARN=""

for _ in {1..15}; do
  ALB_ARN=$(aws elbv2 describe-load-balancers \
    --region "$AWS_REGION" \
    --query "LoadBalancers[?contains(LoadBalancerName, 'kubapp')].LoadBalancerArn | [0]" \
    --output text)

  if [[ -n "$ALB_ARN" && "$ALB_ARN" != "None" ]]; then
    break
  fi

  sleep 10
done

if [[ -z "$ALB_ARN" || "$ALB_ARN" == "None" ]]; then
  echo "❌ ALB not found"
  exit 1
fi

ALB=$(aws elbv2 describe-load-balancers \
  --region "$AWS_REGION" \
  --load-balancer-arns "$ALB_ARN" \
  --query "LoadBalancers[0].DNSName" \
  --output text)

ALB_ZONE_ID=$(aws elbv2 describe-load-balancers \
  --region "$AWS_REGION" \
  --load-balancer-arns "$ALB_ARN" \
  --query "LoadBalancers[0].CanonicalHostedZoneId" \
  --output text)

if [[ -z "$ALB" || "$ALB" == "None" ]]; then
  echo "❌ ALB DNS name not available"
  exit 1
fi

echo "✅ ALB: $ALB"

echo "Updating root domain..."

aws route53 change-resource-record-sets \
  --hosted-zone-id "$ZONE_ID" \
  --change-batch "{
    \"Changes\": [{
      \"Action\": \"UPSERT\",
      \"ResourceRecordSet\": {
        \"Name\": \"$DOMAIN\",
        \"Type\": \"A\",
        \"AliasTarget\": {
          \"HostedZoneId\": \"$ALB_ZONE_ID\",
          \"DNSName\": \"$ALB\",
          \"EvaluateTargetHealth\": false
        }
      }
    }]
  }"

for svc in "${SERVICES[@]}"; do
  FQDN="$svc.$DOMAIN"

  echo "Syncing: $FQDN"

  aws route53 change-resource-record-sets \
    --hosted-zone-id "$ZONE_ID" \
    --change-batch "{
      \"Changes\": [{
        \"Action\": \"UPSERT\",
        \"ResourceRecordSet\": {
          \"Name\": \"$FQDN\",
          \"Type\": \"A\",
          \"AliasTarget\": {
            \"HostedZoneId\": \"$ALB_ZONE_ID\",
            \"DNSName\": \"$ALB\",
            \"EvaluateTargetHealth\": false
          }
        }
      }]
    }"

  echo "✅ $FQDN synced"
done

echo "===================================="
echo "DNS SYNC COMPLETE"
echo "===================================="
