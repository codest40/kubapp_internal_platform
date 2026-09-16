#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# MODE
# ============================================================
MODE="${1:-first_run}"   # first_run | apply | destroy

# ============================================================
# CONFIG
# ============================================================
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TF_DIR="$PROJECT_ROOT/infra/aws"

DOMAIN="sys-monitor.rundailytest.site"
EMAIL="rundailytest@gmail.com"

KEY_NAME="tf-web-key"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/${KEY_NAME}.pem}"

REMOTE_DIR="/opt/sys_monitor"

cd "$TF_DIR"

# ============================================================
# DESTROY MODE
# ============================================================
if [[ "$MODE" == "destroy" ]]; then
  echo "🔥 DESTROY MODE"
  terraform destroy -auto-approve
  exit 0
fi

# ============================================================
# TERRAFORM INIT
# ============================================================
terraform init -upgrade

echo "==> Terraform apply"
terraform apply -auto-approve \
  -var="key_name=${KEY_NAME}" \
  -var="ssh_cidr=$(curl -s ifconfig.me)/32"

PUBLIC_IP="$(terraform output -raw public_ip)"

echo "EC2: $PUBLIC_IP"

ssh-keygen -R "$PUBLIC_IP" >/dev/null 2>&1 || true

# ============================================================
# WAIT FOR SSH
# ============================================================
echo "==> Waiting SSH..."
for i in {1..40}; do
  ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" ubuntu@"$PUBLIC_IP" "echo ok" && break
  sleep 5
done

# ============================================================
# FIRST RUN BOOTSTRAP
# ============================================================
if [[ "$MODE" == "first_run" ]]; then
  echo "==> Waiting for cloud-init"
  ssh -i "$SSH_KEY" ubuntu@"$PUBLIC_IP" << 'EOF'
set -e
while [ ! -f /var/lib/cloud/instance/boot-finished ]; do
  sleep 5
done
EOF
fi

# ============================================================
# SYNC CODE
# ============================================================
echo "==> Syncing code"

rsync -az --delete \
  -e "ssh -i $SSH_KEY -o StrictHostKeyChecking=no" \
  --exclude ".git" \
  --exclude ".terraform" \
  "$PROJECT_ROOT/" \
  ubuntu@"$PUBLIC_IP":"$REMOTE_DIR/"

# ============================================================
# REMOTE DEPLOY
# ============================================================
ssh -i "$SSH_KEY" ubuntu@"$PUBLIC_IP" << EOF
set -euo pipefail

cd /opt/sys_monitor

# ============================================================
# START CONTAINERS
# ============================================================
echo "==> Starting containers"

docker compose down -v || true
docker compose up -d --build

# ============================================================
# WAIT FOR SERVICES (HTTP READINESS)
# ============================================================
echo "==> Waiting for service readiness..."

for i in {1..60}; do

  GRAFANA_OK=\$(curl -fs http://localhost:3001/api/health >/dev/null && echo ok || echo no)
  PROM_OK=\$(curl -fs http://localhost:9090/-/ready >/dev/null && echo ok || echo no)
  EXPORTER_OK=\$(curl -fs http://localhost:3000/ >/dev/null && echo ok || echo no)

  echo "grafana=\$GRAFANA_OK prom=\$PROM_OK exporter=\$EXPORTER_OK"

  if [[ "\$GRAFANA_OK" == "ok" && "\$PROM_OK" == "ok" && "\$EXPORTER_OK" == "ok" ]]; then
    echo "All services READY"
    break
  fi

  sleep 5
done

# ============================================================
# STEP 1: INSTALL HTTP NGINX (BOOTSTRAP SAFE)
# ============================================================
echo "==> Installing HTTP nginx config"

sudo cp infra/aws/nginx.http.conf /etc/nginx/sites-available/sys-monitor
sudo ln -sf /etc/nginx/sites-available/sys-monitor \
            /etc/nginx/sites-enabled/sys-monitor

sudo nginx -t
sudo systemctl restart nginx

# ============================================================
# STEP 2: ISSUE CERTIFICATE (NO CONFIG CHANGE)
# ============================================================
echo "==> Issuing SSL certificate"

sudo certbot certonly --nginx \
  -d "$DOMAIN" \
  -m "$EMAIL" \
  --agree-tos \
  --non-interactive

# ============================================================
# STEP 3: ENABLE SSL NGINX CONFIG
# ============================================================
echo "==> Enabling HTTPS nginx config"

sudo rm -f /etc/nginx/sites-enabled/default || true

sudo cp infra/aws/nginx.ssl.conf /etc/nginx/sites-available/sys-monitor
sudo ln -sf /etc/nginx/sites-available/sys-monitor \
            /etc/nginx/sites-enabled/sys-monitor

sudo nginx -t
sudo systemctl restart nginx

# ============================================================
# FINAL CHECK
# ============================================================
echo "==> System check"

curl -fs http://127.0.0.1:3000/ || true
curl -fs http://127.0.0.1:3001/api/health || true
curl -fs http://127.0.0.1:9090/-/ready || true

echo "DONE"
EOF

# ============================================================
# OUTPUT
# ============================================================
echo ""
echo "========================================"
echo "DEPLOYMENT COMPLETE"
echo "========================================"
echo "Routes:"
echo "  https://$DOMAIN/grafana/"
echo "  https://$DOMAIN/prometheus/"
echo "  https://$DOMAIN/webhook/github"
echo "========================================"
echo "EC2 IP: $PUBLIC_IP"
echo "========================================"
