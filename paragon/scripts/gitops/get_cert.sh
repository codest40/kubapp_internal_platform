#!/usr/bin/env bash
set -euo pipefail

DOMAIN="${1:-${DOMAIN:-}}"

if [[ -z "$DOMAIN" ]]; then
  echo "Usage: $0 <domain>" >&2
  exit 1
fi

CERT_ARNS=$(aws acm list-certificates \
  --query "CertificateSummaryList[].CertificateArn" \
  --output text)

FOUND=""

for arn in $CERT_ARNS; do
  DOMAINS=$(aws acm describe-certificate \
    --certificate-arn "$arn" \
    --query "Certificate.SubjectAlternativeNames" \
    --output text)

  for d in $DOMAINS; do
    if [[ "$d" == "$DOMAIN" ]]; then
      FOUND="$arn"
      break 2
    fi
  done
done

if [[ -z "$FOUND" ]]; then
  echo "❌ DOMAIN NOT FOUND IN ACM: $DOMAIN" >&2
  exit 1
fi

echo "$FOUND"
