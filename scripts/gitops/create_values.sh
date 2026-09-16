#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# STATIC VALUES BUILDER
# =========================================================

ARTIFACT_FILE="${1:-}"
ROLE_ARN="${IRSA_ARN:-}"
SERVICE_TYPE="${SERVICE_TYPE:-}"
REPLICA_COUNT="${REPLICA_COUNT:-2}"
HPA_ENABLED="${HPA_ENABLED:-false}"

fail() {
  echo "❌ $1"
  exit 1
}

require() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing dependency: $1"
}

line() {
  printf '%*s\n' "${1:-60}" '' | tr ' ' '#'
}

banner() {
  line
  line
  echo ">>> SCRIPT: $0 <<<"
  echo " Building static values for $1 with $2"
  line
  line
}

normalize_name() {
  local name="$1"
  if [[ "$name" == *_* || "$name" == *.* ]]; then
    name="${name//_/-}"
    name="${name//./-}"
  fi
  echo "$name"
}

[[ -n "$ARTIFACT_FILE" ]] || fail "Usage: create_values.sh <artifact-json>"
[[ -f "$ARTIFACT_FILE" ]] || fail "Artifact not found: $ARTIFACT_FILE"

SVC_TYPE=$(jq -r '.type' "$ARTIFACT_FILE")
[[ "$SERVICE_TYPE" == "App" && "$SVC_TYPE" == "$SERVICE_TYPE" ]] || fail "Service Type Not found OR Doesnt Match: $SERVICE_TYPE != $SVC_TYPE"

require jq
require yq

SERVICE=$(jq -r '.service // ""' "$ARTIFACT_FILE")
[[ -n "$SERVICE" ]] || fail "❌ Service does Not exit"
ENV=$(jq -r '.env // "dev"' "$ARTIFACT_FILE")
NAMESPACE=$(jq -r '.namespace // ""' "$ARTIFACT_FILE")
[[ -n "$NAMESPACE" ]] || fail "❌ Namespace does Not exit"

PORT=$(jq -r '.port // ""' "$ARTIFACT_FILE")
IMAGE=$(jq -r '.image // ""' "$ARTIFACT_FILE")
TAG=$(jq -r '.tag // ""' "$ARTIFACT_FILE")
CONTAINER_UID=$(jq -r '.containerUid // 10001' "$ARTIFACT_FILE")
HEALTH=$(jq -r '.healthPath // "/health"' "$ARTIFACT_FILE")
LIVE=$(jq -r '.livePath // "/live"' "$ARTIFACT_FILE")
TMP_VOL=$(jq -r '.tmp_volume // ""' "$ARTIFACT_FILE")
MNT_VOL=$(jq -r '.mount_vol // ""' "$ARTIFACT_FILE")
MNT_PATH=$(jq -r '.mount_path // ""' "$ARTIFACT_FILE")
TMP_ENABLED=$(jq -r '.tmp_enabled // false' "$ARTIFACT_FILE")
SVC_MONITOR_ENAB=$(jq -r '.svc_monitor_enabled // false' "$ARTIFACT_FILE")
NO_SECRETS=$(jq -r '.NO_SECRETS // false' "$ARTIFACT_FILE")
SECRET_NAME="${SERVICE}-secrets"
COMPUTE_TYPE=$(jq -r '.computeType // "fargate"' "$ARTIFACT_FILE")

TARGET_SERVICE=$(normalize_name "$SERVICE")
TARGET_DIR="gitops/envs/$ENV/apps/$TARGET_SERVICE"
TARGET_FILE="$TARGET_DIR/values.yaml"

mkdir -p "$TARGET_DIR"

banner "$SERVICE" "$COMPUTE_TYPE"

####################################################
# STATIC FINGERPRINT
####################################################
STATIC_FP=$(echo -n "$SERVICE|$NAMESPACE|$PORT|v1" | sha256sum | awk '{print $1}')
DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

####################################################
# BUILD BASE VALUES (STATIC SOURCE OF TRUTH)
####################################################
cat > /tmp/static-values.yaml <<EOF
appName: $SERVICE
namespace: $NAMESPACE

serviceAccount:
  create: true
  name: ${SERVICE}-sa
  roleArn: $ROLE_ARN

serviceMonitor:
  enabled: $SVC_MONITOR_ENAB
  path: /metrics
  interval: 30s

replicaCount: $REPLICA_COUNT

image:
  repository: $IMAGE
  tag: $TAG
  pullPolicy: Always

service:
  type: ClusterIP
  port: 80
  targetPort: $PORT

resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 300m
    memory: 256Mi

env: {}

securityContext:
  pod:
    runAsNonRoot: true
    seccompProfile:
      type: RuntimeDefault

  container:
    runAsNonRoot: true
    runAsUser: ${CONTAINER_UID}
    allowPrivilegeEscalation: false
    readOnlyRootFilesystem: true
    capabilities:
      drop:
        - ALL

probes:
  readiness:
    httpGet:
      path: ${HEALTH}
      port: ${PORT}
    initialDelaySeconds: 5
    periodSeconds: 10

  liveness:
    httpGet:
      path: ${LIVE}
      port: ${PORT}
    initialDelaySeconds: 10
    periodSeconds: 15

hpa:
  enabled: $HPA_ENABLED
  minReplicas: 2
  maxReplicas: 4
  cpu: 70
  memory: 70

meta:
  staticFingerprint: $STATIC_FP
  generatedAt: $DATE
  source: build-pipeline
EOF

####################################################
# STORAGE (NO DUPLICATES BY DESIGN)
####################################################
if [[ "$TMP_ENABLED" == "true" && -n "$TMP_VOL" && -n "$MNT_VOL" && -n "$MNT_PATH" ]]; then
cat >> /tmp/static-values.yaml <<EOF

storage:
  volumes:
    - name: ${TMP_VOL}
      emptyDir: {}

  volumeMounts:
    - name: ${MNT_VOL}
      mountPath: ${MNT_PATH}
EOF
fi

####################################################
# SECRETS
####################################################
if [[ "$NO_SECRETS" == "false" && -n "$SECRET_NAME" ]]; then
cat >> /tmp/static-values.yaml <<EOF
secret:
  enabled: true
  name: $SECRET_NAME
EOF
else
  echo "$SERVICE App has No secret: NO_SECRETS=$NO_SECRETS"
fi

####################################################
# COMPUTE MODE (SINGLE SOURCE OF TRUTH)
####################################################

yq eval -i '
  del(.labels.compute) |
  del(.nodeSelector) |
  del(.tolerations)
' /tmp/static-values.yaml

case "$COMPUTE_TYPE" in
  fargate)
    yq eval -i '.labels.compute = "fargate"' /tmp/static-values.yaml
    ;;

  node|ec2)
    yq eval -i '
      .nodeSelector.compute = "ec2" |
      .tolerations = [{
        "key": "compute",
        "operator": "Equal",
        "value": "ec2",
        "effect": "NoSchedule"
      }]
    ' /tmp/static-values.yaml
    ;;
  *)
    fail "Unknown COMPUTE_TYPE: $COMPUTE_TYPE"
    ;;
esac

# FINAL WRITE (NO MERGE - FULL OVERRIDE)
cp /tmp/static-values.yaml "$TARGET_FILE"

# FINAL PATCH
yq e -i ".meta.staticFingerprint = \"$STATIC_FP\"" "$TARGET_FILE"

echo "✅ Static values ready: $TARGET_FILE"
cat "$TARGET_FILE"
