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

BACKEND_ENV_PARAMETER="/sys-monitor/backend/env"

# --------------------------------------------------
# System packages
# --------------------------------------------------

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
# Application repository
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

if [[ ! -d "$APP_DIR" ]]; then
    echo "ERROR: Application directory not found: $APP_DIR"
    exit 1
fi

# --------------------------------------------------
# Backend runtime configuration
# --------------------------------------------------

echo "Retrieving backend configuration from SSM Parameter Store..."

mkdir -p "$APP_DIR/backend"

# Do not print the retrieved parameter value to the deployment log.
aws ssm get-parameter \
    --name "$BACKEND_ENV_PARAMETER" \
    --with-decryption \
    --region "$AWS_REGION" \
    --query 'Parameter.Value' \
    --output text \
    > "$APP_DIR/backend/.env"

chmod 600 "$APP_DIR/backend/.env"

if [[ ! -s "$APP_DIR/backend/.env" ]]; then
    echo "ERROR: Backend environment configuration is missing or empty."
    exit 1
fi

echo "Backend environment configuration retrieved successfully."

# --------------------------------------------------
# Edge setup
# --------------------------------------------------

EDGE_SETUP="$REPO_DIR/sys_monitor/cloud/aws/main/edge_setup.sh"

if [[ ! -f "$EDGE_SETUP" ]]; then
    echo "ERROR: Edge setup script not found: $EDGE_SETUP"
    exit 1
fi

chmod +x "$EDGE_SETUP"
source "$EDGE_SETUP"

# --------------------------------------------------
# Runtime configuration for existing exporters
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

echo "Generated exporter runtime configuration."

# --------------------------------------------------
# Validate Compose configuration
# --------------------------------------------------

cd "$APP_DIR"

echo "Validating Docker Compose configuration..."

docker compose config --quiet

# --------------------------------------------------
# Build and start services
# --------------------------------------------------

echo "Building and starting sys_monitor services..."

docker compose pull
docker compose up -d --build


# --------------------------------------------------
# Health checks
# --------------------------------------------------
wait_for_dns() {
    local hosts=(
        "graf.$${DOMAIN}"
        "prom.$${DOMAIN}"
        "git.$${DOMAIN}"
        "codebase.$${DOMAIN}"
        "gitops.$${DOMAIN}"
        "monitor.$${DOMAIN}"
    )

    echo "Waiting for public DNS records..."

    for attempt in {1..60}; do
        local all_resolved=true

        for host in "$${hosts[@]}"; do
            if ! getent ahostsv4 "$host" >/dev/null 2>&1; then
                echo "DNS not ready: $host"
                all_resolved=false
            fi
        done

        if [[ "$all_resolved" == true ]]; then
            echo "All required hostnames resolve."
            return 0
        fi

        sleep 10
    done

    echo "ERROR: DNS records did not resolve within 10 minutes."
    return 1
}

echo "========================================"
echo "WAITING FOR SERVICES"
echo "========================================"

for i in {1..60}; do

    PROM=$(curl -fs http://localhost:9090/-/ready >/dev/null && echo ok || echo no)

    GRAFANA=$(curl -fs http://localhost:3001/api/health >/dev/null && echo ok || echo no)

    GITHUB=$(curl -fs http://localhost:3000/ >/dev/null && echo ok || echo no)

    GITOPS=$(curl -fs http://localhost:9105/ >/dev/null && echo ok || echo no)

    CODEBASE=$(curl -fs http://localhost:8080/ >/dev/null && echo ok || echo no)

    BACKEND=$(curl -fs http://localhost:8001/health >/dev/null && echo ok || echo no)

    FRONTEND=$(curl -fs http://localhost:4173/ >/dev/null && echo ok || echo no)

    echo "prom=$PROM grafana=$GRAFANA github=$GITHUB gitops=$GITOPS codebase=$CODEBASE backend=$BACKEND frontend=$FRONTEND"

    if [[ "$PROM" == "ok" &&
          "$GRAFANA" == "ok" &&
          "$GITHUB" == "ok" &&
          "$GITOPS" == "ok" &&
          "$CODEBASE" == "ok" &&
          "$BACKEND" == "ok" &&
          "$FRONTEND" == "ok" ]]; then

        echo "========================================"
        echo "SYS_MONITOR SERVICES READY"
        echo "========================================"

        setup_nginx
        wait_for_dns
        setup_tls
        setup_cert_renewal

        echo "========================================"
        echo "SYS_MONITOR EDGE READY"
        echo "Dashboard: https://monitor.$DOMAIN"
        echo "========================================"

        exit 0
    fi

    sleep 10
done

echo "SYS_MONITOR FAILED HEALTH CHECK"

docker compose ps

docker compose logs --tail=100 backend frontend

exit 1
