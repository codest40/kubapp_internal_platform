#!/usr/bin/env bash

set -euo pipefail

DOMAIN="${DOMAIN:-rundailytest.online}"
ZONE_ID="${ZONE_ID:?ZONE_ID is required}"
ING_FILE="${INGRESS_FILE:-gitops/ingress/dev/values.yaml}"
MON_FILE="${MONITORING_FILE:-gitops/ingress/dev/monitoring.yaml}"
ARGO_FILE="${ARGO_FILE:-gitops/ingress/dev/argocd.yaml}"

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"

if [[ -z "$ROOT" ]]; then
    echo "❌ Unable to determine project root."
    exit 1
fi

ING_FILE="$ROOT/$ING_FILE"
MON_FILE="$ROOT/$MON_FILE"
ARGO_FILE="$ROOT/$ARGO_FILE"

for file in "$ING_FILE" "$MON_FILE" "$ARGO_FILE"; do
    if [[ ! -f "$file" ]]; then
        echo "❌ File not found: $file"
        exit 1
    fi
done

echo "===================================="
echo "ORPHAN DNS CLEANUP"
echo "DOMAIN:  $DOMAIN"
echo "ZONE_ID: $ZONE_ID"
echo "===================================="

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

mapfile -t CURRENT_SERVICES <<< "$ALL_SERVICES"

echo
echo "Current services:"
printf ' - %s\n' "${CURRENT_SERVICES[@]}"

echo
echo "Scanning Route53..."

EXISTING=$(aws route53 list-resource-record-sets \
    --hosted-zone-id "$ZONE_ID")

while IFS= read -r record; do

    NAME=$(echo "$record" | jq -r '.Name')
    TYPE=$(echo "$record" | jq -r '.Type')

    ROOT_DOMAIN="${DOMAIN}."

    if [[ "$NAME" == "$ROOT_DOMAIN" ]]; then
        echo "KEEP: root domain: $NAME"
        continue
    fi

    if [[ "$TYPE" == "NS" || "$TYPE" == "SOA" ]]; then
        echo "KEEP: protected record: $NAME ($TYPE)"
        continue
    fi

    if [[ "$TYPE" != "A" &&
          "$TYPE" != "AAAA" &&
          "$TYPE" != "CNAME" ]]; then
        echo "KEEP: unsupported record: $NAME ($TYPE)"
        continue
    fi

    SUBDOMAIN="${NAME%.}"
    SUBDOMAIN="${SUBDOMAIN%.$DOMAIN}"

    KEEP=false

    for svc in "${CURRENT_SERVICES[@]}"; do
        if [[ "$SUBDOMAIN" == "$svc" ]]; then
            KEEP=true
            break
        fi
    done

    if [[ "$KEEP" == true ]]; then
        echo "KEEP: active service: $NAME"
        continue
    fi

    echo "ORPHAN: $NAME ($TYPE)"
    echo "Deleting..."

    aws route53 change-resource-record-sets \
        --hosted-zone-id "$ZONE_ID" \
        --change-batch "$(jq -n \
            --argjson record "$record" \
            '{
                Changes: [
                    {
                        Action: "DELETE",
                        ResourceRecordSet: $record
                    }
                ]
            }'
        )"

    echo "✓ Deleted: $NAME"

done < <(
    echo "$EXISTING" |
    jq -c '.ResourceRecordSets[]'
)

echo
echo "===================================="
echo "ORPHAN DNS CLEANUP COMPLETE"
echo "===================================="
