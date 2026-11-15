#!/usr/bin/env bash

set -euo pipefail

TARGET_ACCOUNT_ID="${SYS_MONITOR_ACCOUNT_ID:?SYS_MONITOR_ACCOUNT_ID Required}"
SESSION_NAME="sys-monitor-deployment"
ROLE_INPUT="${AWS_ROLE_ARN:?AWS_ROLE_ARN is required}"
ROLE_NAME="${ROLE_INPUT##*/}"
ROLE_ARN="arn:aws:iam::${TARGET_ACCOUNT_ID}:role/${ROLE_NAME}"

echo "Switching AWS identity..."
echo "Target account: $TARGET_ACCOUNT_ID"
echo "Target role: $ROLE_ARN"

: "${ACTIONS_ID_TOKEN_REQUEST_TOKEN:?GitHub OIDC token unavailable}"
: "${ACTIONS_ID_TOKEN_REQUEST_URL:?GitHub OIDC URL unavailable}"

OIDC_RESPONSE=$(curl -fsS \
    -H "Authorization: Bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
    "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=sts.amazonaws.com")

OIDC_TOKEN=$(jq -er '.value' <<< "$OIDC_RESPONSE")

CREDENTIALS=$(aws sts assume-role-with-web-identity \
    --role-arn "$ROLE_ARN" \
    --role-session-name "$SESSION_NAME" \
    --web-identity-token "$OIDC_TOKEN" \
    --duration-seconds 3600)

ACCESS_KEY=$(jq -er '.Credentials.AccessKeyId' <<< "$CREDENTIALS")
SECRET_KEY=$(jq -er '.Credentials.SecretAccessKey' <<< "$CREDENTIALS")
SESSION_TOKEN=$(jq -er '.Credentials.SessionToken' <<< "$CREDENTIALS")

ACTUAL_ACCOUNT=$(AWS_ACCESS_KEY_ID="$ACCESS_KEY" \
    AWS_SECRET_ACCESS_KEY="$SECRET_KEY" \
    AWS_SESSION_TOKEN="$SESSION_TOKEN" \
    aws sts get-caller-identity --query Account --output text)

if [[ "$ACTUAL_ACCOUNT" != "$TARGET_ACCOUNT_ID" ]]; then
    echo "ERROR: Failed to switch to target AWS account."
    echo "Expected: $TARGET_ACCOUNT_ID"
    echo "Actual: $ACTUAL_ACCOUNT"
    exit 1
fi

echo "::add-mask::$ACCESS_KEY"
echo "::add-mask::$SECRET_KEY"
echo "::add-mask::$SESSION_TOKEN"

{
    echo "AWS_ACCESS_KEY_ID=$ACCESS_KEY"
    echo "AWS_SECRET_ACCESS_KEY=$SECRET_KEY"
    echo "AWS_SESSION_TOKEN=$SESSION_TOKEN"
    echo "AWS_ACCOUNT_ID=$TARGET_ACCOUNT_ID"
} >> "$GITHUB_ENV"

echo "AWS identity successfully switched."
echo "Active account: $ACTUAL_ACCOUNT"

unset OIDC_TOKEN OIDC_RESPONSE CREDENTIALS
unset ACCESS_KEY SECRET_KEY SESSION_TOKEN
