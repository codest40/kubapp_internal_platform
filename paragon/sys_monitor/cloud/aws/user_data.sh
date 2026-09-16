#!/bin/bash
set -euxo pipefail

# ============================================================
# LOGGING
# ============================================================
exec > /var/log/user-data.log 2>&1

echo "========================================"
echo "USER DATA START"
date
echo "========================================"

# ============================================================
# BASE SYSTEM
# ============================================================
apt-get update -y

apt-get install -y \
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  git \
  dnsutils \
  unzip \
  jq

# ============================================================
# DOCKER (OFFICIAL STABLE WAY)
# ============================================================

echo "Installing Docker official repo..."

install -m 0755 -d /etc/apt/keyrings

curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

chmod a+r /etc/apt/keyrings/docker.gpg

echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu \
$(. /etc/os-release && echo $VERSION_CODENAME) stable" \
> /etc/apt/sources.list.d/docker.list

apt-get update -y

apt-get install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin

# ============================================================
# START DOCKER
# ============================================================
systemctl enable docker
systemctl start docker

usermod -aG docker ubuntu || true

# ============================================================
# AWS CLI v2
# ============================================================
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install
rm -rf /tmp/aws /tmp/awscliv2.zip

# ============================================================
# KUBECTL
# ============================================================
K8S_VERSION="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"

curl -fsSL "https://dl.k8s.io/release/${K8S_VERSION}/bin/linux/amd64/kubectl" \
  -o /usr/local/bin/kubectl

chmod +x /usr/local/bin/kubectl

# ============================================================
# APP DIRECTORY
# ============================================================
mkdir -p /opt/sys_monitor
chown -R ubuntu:ubuntu /opt/sys_monitor
chmod 755 /opt/sys_monitor

# ============================================================
# VERIFY INSTALLS
# ============================================================
echo "Docker version:"
docker --version || true

echo "AWS CLI version:"
aws --version || true

echo "kubectl version:"
kubectl version --client || true

# ============================================================
# ENV EXPORTS
# ============================================================
cat <<EOF >> /home/ubuntu/.bashrc
export AWS_REGION=us-east-1
export AWS_DEFAULT_REGION=us-east-1
EOF

chown ubuntu:ubuntu /home/ubuntu/.bashrc

echo "========================================"
echo "USER DATA COMPLETE"
echo "========================================"
