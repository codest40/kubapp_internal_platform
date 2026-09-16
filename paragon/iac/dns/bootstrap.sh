#!/usr/bin/env bash

set -euo pipefail

ACTION="${1:-create}"

PROFILE="${PROFILE:-}"
REGION="${REGION:-us-east-1}"

if [[ -z "$PROFILE" ]]; then
  PROFILE="${AWS_PROFILE:-}"
  if [[ -z "$PROFILE" ]]; then
    echo "Profile CANNOT Be Empty. Supply it"
    exit 1
  fi
  echo "AWS_PROFILE: $PROFILE"
fi

ACCOUNT_ID="$(aws sts get-caller-identity \
  --profile "$PROFILE" \
  --query Account \
  --output text)"

BUCKET="kubapp-dns-tf-state-${ACCOUNT_ID}"

echo "AWS account : $ACCOUNT_ID"
echo "AWS region  : $REGION"
echo "State bucket: $BUCKET"

delete_bucket() {
  echo
  echo "WARNING: This will permanently delete:"
  echo "  $BUCKET"
  echo
  echo "This bucket contains Terraform state."
  echo

  read -r -p "Type DELETE to continue: " CONFIRM

  if [[ "$CONFIRM" != "DELETE" ]]; then
    echo "Deletion cancelled."
    exit 1
  fi

  if ! aws s3api head-bucket \
    --bucket "$BUCKET" \
    --profile "$PROFILE" \
    >/dev/null 2>&1; then
    echo "State bucket does not exist."
    return 0
  fi

  echo
  echo "Deleting all object versions and delete markers..."

  while true; do
    OBJECTS="$(
      aws s3api list-object-versions \
        --bucket "$BUCKET" \
        --profile "$PROFILE" \
        --output json |
      jq -c '
        [
          (.Versions // [])[],
          (.DeleteMarkers // [])[]
        ]
        | map({
            Key: .Key,
            VersionId: .VersionId
          })
      '
    )"

    if [[ "$OBJECTS" == "[]" ]]; then
      break
    fi

    jq -n \
      --argjson objects "$OBJECTS" \
      '{Objects: $objects, Quiet: true}' |
    aws s3api delete-objects \
      --bucket "$BUCKET" \
      --profile "$PROFILE" \
      --delete file:///dev/stdin
  done

  echo "Deleting bucket..."

  aws s3api delete-bucket \
    --bucket "$BUCKET" \
    --profile "$PROFILE" \
    --region "$REGION"

  echo
  echo "DNS state bucket deleted."
}

create_bucket() {
  echo "CREATING BACKEND..."
  if aws s3api head-bucket \
    --bucket "$BUCKET" \
    --profile "$PROFILE" \
    >/dev/null 2>&1; then

    echo "State bucket already exists."

  else

    echo "Creating DNS Terraform state bucket..."

    if [[ "$REGION" == "us-east-1" ]]; then
      aws s3api create-bucket \
        --bucket "$BUCKET" \
        --region "$REGION" \
        --profile "$PROFILE"
    else
      aws s3api create-bucket \
        --bucket "$BUCKET" \
        --region "$REGION" \
        --create-bucket-configuration LocationConstraint="$REGION" \
        --profile "$PROFILE"
    fi
  fi

  aws s3api put-bucket-versioning \
    --bucket "$BUCKET" \
    --versioning-configuration Status=Enabled \
    --profile "$PROFILE"

  aws s3api put-bucket-encryption \
    --bucket "$BUCKET" \
    --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}' \
    --profile "$PROFILE"

  aws s3api put-public-access-block \
    --bucket "$BUCKET" \
    --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true \
    --profile "$PROFILE"

  echo
  echo "DNS backend ready."
  echo
  echo "bucket = $BUCKET"
  echo "region = $REGION"
}

case "$ACTION" in
  create)
    create_bucket
    ;;
  delete)
    delete_bucket
    ;;
  *)
    echo "Unknown action: $ACTION"
    echo
    echo "Usage:"
    echo "  ./bootstrap.sh create"
    echo "  ./bootstrap.sh delete"
    exit 1
    ;;
esac
