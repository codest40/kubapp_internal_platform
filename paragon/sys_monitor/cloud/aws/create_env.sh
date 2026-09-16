#!/usr/bin/env bash
set -euo pipefail

# -------- INPUTS --------
MODE="${MODE:-local}"
ACCOUNT_ID="${ACCOUNT_ID:?ACCOUNT_ID is required}"
ENABLE_NODE_DEBUG="${ENABLE_NODE_DEBUG:-false}"

TARGET_CLUSTER_NAME="${TARGET_CLUSTER_NAME:-kubapp-dev}"
TARGET_REGION="${TARGET_REGION:-us-east-1}"
AWS_REGION="${AWS_REGION:-us-east-1}"

ENV_FILE="/opt/sys_monitor/.env"

# -------- LOGIC --------
TARGET_ROLE_ARN=""

if [[ "$MODE" == "cross" ]]; then
  CLUSTER_MODE="cross"
  TARGET_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/sys-monitor-cross-account-role"
  echo "Cross-account mode enabled"
else
  CLUSTER_MODE="local"
  echo "Local mode enabled"
fi

# -------- WRITE .ENV --------
cat > "$ENV_FILE" <<EOF
CLUSTER_MODE=${CLUSTER_MODE}
ENABLE_NODE_DEBUG=${ENABLE_NODE_DEBUG}
TARGET_ROLE_ARN=${TARGET_ROLE_ARN}
TARGET_CLUSTER_NAME=${TARGET_CLUSTER_NAME}
TARGET_REGION=${TARGET_REGION}
AWS_REGION=${AWS_REGION}
ACCOUNT_ID=${ACCOUNT_ID}
EOF

echo ".env generated successfully:"
cat "$ENV_FILE"
echo "=============================================="
echo "ENV GENERATION START"
echo "Path: $ENV_FILE"
echo "Mode: $MODE"
echo "Account: $ACCOUNT_ID"
echo "=============================================="

