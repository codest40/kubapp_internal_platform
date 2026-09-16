#!/usr/bin/env bash
set -u

# ============================================================
# SAFE EXECUTION FRAMEWORK
# ============================================================

MODE="${1:-first_run}"
ENV="${ENV:-local}"
ACCOUNT_ID="${ACCOUNT_ID:-}"
ENABLE_NODE_DEBUG="${ENABLE_NODE_DEBUG:-true}"
KEY_NAME="${KEY_NAME:-}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/${KEY_NAME}.pem}"

REMOTE_DIR="/opt/sys_monitor"
DOMAIN="${DOMAIN:-rundailytest.site}"
ZONE_ID="${ZONE_ID:-}"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if [[ "$MODE" == "destroy" ]]; then
  echo "Destroying Activated..."
  terraform destroy -auto-approve \
    -var="enable_route53=false" \
    -target=aws_vpc.sys_vpc \
    -target=aws_subnet.public_subnet \
    -target=aws_internet_gateway.igw \
    -target=aws_route_table.public_rt \
    -target=aws_route_table_association.public_assoc \
    -target=aws_security_group.sys_monitor \
    -target=aws_instance.sys_monitor \
    -target=aws_eip.sys_eip \
    -target=aws_iam_role.sys_monitor_local_role \
    -target=aws_iam_role_policy.cross_assume \
    -target=aws_iam_instance_profile.sys_monitor_local_profile

  MODE=auto bash boot/runner.sh destroy
  exit 1
fi

# ---------------- ERROR HANDLER ----------------
fail() {
  echo ""
  echo "========================================"
  echo "❌ CONTROLLED FAILURE"
  echo "STEP: $1"
  echo "REASON: $2"
  echo "EXIT CODE: $3"
  echo "========================================"
  exit "$3"
}

log() { echo "==> $1"; }

# ============================================================
# VALIDATION
# ============================================================
for v in ACCOUNT_ID KEY_NAME SSH_KEY; do
  if [[ -z "${!v:-}" || "${!v}" == "null" ]]; then
    fail "VALIDATION" "$v missing" 10
  fi
done

# ============================================================
# ROUTE53 AUTO-IMPORT GUARD
# ============================================================

log "Checking Route53 drift (auto-import safeguard)"

if [[ -n "$ZONE_ID" && "$ZONE_ID" != "null" ]]; then
  for SUB in app monitor; do
    FULL="${SUB}.${DOMAIN}"
    EXISTS=$(aws route53 list-resource-record-sets \
      --hosted-zone-id "$ZONE_ID" \
      --query "ResourceRecordSets[?Name=='${FULL}.'] | length(@)" \
      --output text)

    if [[ "$EXISTS" != "0" ]]; then
      log "Route53 dns record exists in Target account"
    else
      log "Route53 record does not exist yet: $FULL (Terraform will create it)"
    fi
  done
fi

log "Terraform init"
terraform init -upgrade || fail "TF_INIT" "failed" 20

log "Terraform apply"
terraform apply -auto-approve \
  -var="enable_route53=true" \
  -var="cluster_mode=${ENV}" \
  -var="key_name=${KEY_NAME}" \
  -var="ssh_cidr=$(curl -s ifconfig.me)/32" \
  || fail "TF_APPLY" "failed" 21

PUBLIC_IP="$(terraform output -raw public_ip || true)"

[[ -n "$PUBLIC_IP" ]] || fail "OUTPUT" "missing public_ip" 22

log "EC2 IP: $PUBLIC_IP"

ssh-keygen -R "$PUBLIC_IP" >/dev/null 2>&1 || true

# ============================================================
# SSH WAIT
# ============================================================
log "Waiting for SSH"

for i in {1..40}; do
  ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" ubuntu@"$PUBLIC_IP" "echo ok" >/dev/null 2>&1 && break
  sleep 5
done

# ============================================================
# CLOUD INIT
# ============================================================
log "Cloud-init wait"

ssh -i "$SSH_KEY" ubuntu@"$PUBLIC_IP" "cloud-init status --wait || true"

# ============================================================
# ENSURE REMOTE DIR
# ============================================================
ssh -i "$SSH_KEY" ubuntu@"$PUBLIC_IP" \
"sudo mkdir -p /opt/sys_monitor && sudo chown -R ubuntu:ubuntu /opt/sys_monitor"

# ============================================================
# RSYNC (LOCAL ONLY — FIXED)
# ============================================================
log "Syncing project"

rsync -azvv --delete \
  -e "ssh -i $SSH_KEY -o StrictHostKeyChecking=no" \
  --exclude ".git" \
  --exclude ".terraform" \
  "$PROJECT_ROOT/" \
  ubuntu@"$PUBLIC_IP":"$REMOTE_DIR/" \
  || fail "RSYNC" "sync failed" 40

# ============================================================
# REMOTE DEPLOY (CLEAN SINGLE LAYER)
# ============================================================
log "Remote deploy"

ssh -i "$SSH_KEY" ubuntu@"$PUBLIC_IP" <<EOF
set -euo pipefail

echo "========================================"
echo "REMOTE DEPLOY START"
echo "========================================"

cd /opt/sys_monitor

# ---- WAIT FOR DOCKER ----
for i in {1..60}; do
  if command -v docker >/dev/null 2>&1 && systemctl is-active --quiet docker; then
    echo "✅ Docker ready"
    break
  fi
  echo "waiting for docker..."
  sleep 5
done

# ---- FIND ENV SCRIPT ----
SCRIPT_PATH=\$(find . -name create_env.sh | head -n 1)

if [[ -z "\$SCRIPT_PATH" ]]; then
  echo "❌ create_env.sh not found"
  find . -name "*.sh"
  exit 101
fi

echo "Using \$SCRIPT_PATH"

# ---- ENV ----
export ACCOUNT_ID="$ACCOUNT_ID"
export MODE="$ENV"
export ENABLE_NODE_DEBUG="$ENABLE_NODE_DEBUG"

bash "\$SCRIPT_PATH" || echo "ENV generation failed (non-fatal)"

# ---- DOCKER CHECK ----
docker info >/dev/null 2>&1 || { echo "Docker unhealthy"; exit 102; }

# ---- DEPLOY ----
docker compose down -v || true
docker compose up -d --build || exit 103

# ---- HEALTH CHECK ----
for i in {1..60}; do
  GRAFANA=\$(curl -fs http://localhost:3001/api/health >/dev/null && echo ok || echo no)
  PROM=\$(curl -fs http://localhost:9090/-/ready >/dev/null && echo ok || echo no)
  EXPORTER=\$(curl -fs http://localhost:3000/ >/dev/null && echo ok || echo no)
  SRE=\$(curl -fs http://localhost:8000/ >/dev/null && echo ok || echo no)
  GITOPS=\$(curl -fs http://localhost:9105/ >/dev/null && echo ok || echo no)

  echo "grafana=\$GRAFANA prom=\$PROM exporter=\$EXPORTER sre=\$SRE gitops=\$GITOPS"

  [[ "\$GRAFANA" == "ok" && "\$PROM" == "ok" && "\$EXPORTER" == "ok" && "\$SRE" == "ok" && "\$GITOPS" == "ok" ]] && break

  sleep 5
done

echo "========================================"
echo "DEPLOY COMPLETE"
echo "========================================"
EOF

# ============================================================
# FINAL OUTPUT
# ============================================================
echo ""
echo "========================================"
echo "DEPLOYMENT FINISHED"
echo "========================================"
echo ""
echo "EC2 IP: $PUBLIC_IP"
echo "Grafana: http://monitor.${DOMAIN}:3001"
echo "Prometheus: http://monitor.${DOMAIN}:9090"
echo "GitHub Exporter: http://app.${DOMAIN}:3000"
echo "SRE Engine: http://app.${DOMAIN}:8000"
echo "GitOps Exporter: http://app.${DOMAIN}:9105"
echo ""
