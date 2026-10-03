#!/bin/bash
set -euxo pipefail

exec > /var/log/user-data.log 2>&1

echo "========================================"
echo "SYS_MONITOR USER DATA START"
date
echo "========================================"

CLUSTER_MODE="${cluster_mode}"
ACCOUNT_ID="${account_id}"
KUBAPP_ACCOUNT_ID="${kubapp_account_id}"
AWS_REGION="${region}"
DOMAIN="${domain}"

REPO_DIR="/opt/sys_monitor"
APP_DIR="/opt/sys_monitor/sys_monitor"
DEPLOY_KEY="/root/.ssh/sys_monitor_deploy"
REPO_URL="git@github.com:codest40/paragon.git"

dnf update -y

dnf install -y \
    amazon-ssm-agent \
    git \
    jq \
    unzip \
    tar \
    docker

systemctl enable --now amazon-ssm-agent
systemctl enable --now docker

usermod -aG docker ec2-user || true

mkdir -p /usr/local/lib/docker/cli-plugins

# --------------------------------------------------
# Docker Buildx
# --------------------------------------------------

BUILDX_VERSION="v0.29.1"
curl -fL \
    "https://github.com/docker/buildx/releases/download/$${BUILDX_VERSION}/buildx-$${BUILDX_VERSION}.linux-amd64" \
    -o /usr/local/lib/docker/cli-plugins/docker-buildx

chmod +x /usr/local/lib/docker/cli-plugins/docker-buildx

# --------------------------------------------------
# Docker Compose
# --------------------------------------------------

curl -fL \
    https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 \
    -o /usr/local/lib/docker/cli-plugins/docker-compose

chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# --------------------------------------------------
# kubectl
# --------------------------------------------------

curl -fL \
    "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
    -o /tmp/kubectl

chmod +x /tmp/kubectl
mv /tmp/kubectl /usr/local/bin/kubectl

# --------------------------------------------------
# Tool versions
# --------------------------------------------------

echo "AWS CLI:"
aws --version

echo "Docker:"
docker --version

echo "Git:"
git --version

echo "Docker Buildx:"
docker buildx version

echo "Docker Compose:"
docker compose version

echo "kubectl:"
kubectl version --client

# --------------------------------------------------
# GitHub SSH
# --------------------------------------------------

mkdir -p /root/.ssh
chmod 700 /root/.ssh

aws ssm get-parameter \
    --name /sys-monitor/github/deploy-key \
    --with-decryption \
    --region "$AWS_REGION" \
    --query 'Parameter.Value' \
    --output text \
    > "$DEPLOY_KEY"

chmod 600 "$DEPLOY_KEY"

ssh-keyscan github.com > /root/.ssh/known_hosts
chmod 644 /root/.ssh/known_hosts
export GIT_SSH_COMMAND="ssh -i $DEPLOY_KEY -o IdentitiesOnly=yes"


# --------------------------------------------------
# Application
# --------------------------------------------------

mkdir -p "$REPO_DIR"

if [[ ! -d "$REPO_DIR/.git" ]]; then
    echo "Cloning sys_monitor..."

    git clone \
        "$REPO_URL" \
        "$REPO_DIR"
else
    echo "Repository already exists. Updating..."

    git -C "$REPO_DIR" pull --ff-only
fi

mkdir -p "$APP_DIR"

# --------------------------------------------------
# Edge setup
# --------------------------------------------------

EDGE_SETUP="$REPO_DIR/sys_monitor/cloud/aws/main/edge_setup.sh"
if [[ ! -f "$EDGE_SETUP" ]]; then
    echo "ERROR: edge setup script not found:"
    echo "$EDGE_SETUP"
    exit 1
fi

chmod +x "$EDGE_SETUP"
source "$EDGE_SETUP"

# --------------------------------------------------
# Runtime configuration
# --------------------------------------------------

if [[ "$CLUSTER_MODE" == "cross" ]]; then
    TARGET_ROLE_ARN="arn:aws:iam::${kubapp_account_id}:role/sys-monitor-cross-account-role"
else
    TARGET_ROLE_ARN=""
fi

cat > "$APP_DIR/.env" <<EOF
CLUSTER_MODE=$CLUSTER_MODE
TARGET_CLUSTER_NAME=kubapp-dev
TARGET_REGION=$AWS_REGION
TARGET_ROLE_ARN=$TARGET_ROLE_ARN
ENABLE_NODE_DEBUG=false
EOF

chmod 600 "$APP_DIR/.env"

echo "Generated runtime configuration:"
cat "$APP_DIR/.env"

# --------------------------------------------------
# Start services
# --------------------------------------------------

cd "$APP_DIR"

docker compose pull
docker compose up -d --build

echo "========================================"
echo "WAITING FOR SERVICES"
echo "========================================"

for i in {1..60}; do

    PROM=$(curl -fs http://localhost:9090/-/ready >/dev/null && echo ok || echo no)
    GRAFANA=$(curl -fs http://localhost:3001/api/health >/dev/null && echo ok || echo no)
    GITHUB=$(curl -fs http://localhost:3000/ >/dev/null && echo ok || echo no)
    GITOPS=$(curl -fs http://localhost:9105/ >/dev/null && echo ok || echo no)
    CODEBASE=$(curl -fs http://localhost:8080/ >/dev/null && echo ok || echo no)

    echo "prom=$PROM grafana=$GRAFANA github=$GITHUB gitops=$GITOPS codebase=$CODEBASE"

    if [[ "$PROM" == "ok" &&
          "$GRAFANA" == "ok" &&
          "$GITHUB" == "ok" &&
          "$GITOPS" == "ok" &&
          "$CODEBASE" == "ok" ]]; then

        echo "========================================"
        echo "SYS_MONITOR READY"
        echo "========================================"

        setup_nginx
        setup_tls
        setup_cert_renewal

        echo "========================================"
        echo "SYS_MONITOR EDGE READY"
        echo "========================================"

        exit 0
    fi

    sleep 10
done

echo "SYS_MONITOR FAILED HEALTH CHECK"

docker compose ps

exit 1
