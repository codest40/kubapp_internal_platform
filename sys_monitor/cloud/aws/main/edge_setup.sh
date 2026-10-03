#!/bin/bash

set -euo pipefail

DOMAIN="${DOMAIN:-rundailytest.online}"

GRAFANA_HOST="graf.${DOMAIN}"
PROM_HOST="prom.${DOMAIN}"
GITHUB_HOST="git.${DOMAIN}"
CODEBASE_HOST="codebase.${DOMAIN}"
GITOPS_HOST="gitops.${DOMAIN}"

CERTBOT_WEBROOT="/var/www/certbot"
NGINX_CONF="/etc/nginx/conf.d/sys-monitor.conf"


setup_nginx() {
    echo "========================================"
    echo "SETTING UP NGINX"
    echo "========================================"

    dnf install -y \
        nginx \
        certbot \
        python3-certbot-nginx

    mkdir -p "$CERTBOT_WEBROOT/.well-known/acme-challenge"

    chmod 755 "$CERTBOT_WEBROOT"

    cat > "$NGINX_CONF" <<EOF
server {
    listen 80;
    listen [::]:80;

    server_name \
        $GRAFANA_HOST \
        $PROM_HOST \
        $GITHUB_HOST \
        $CODEBASE_HOST \
        $GITOPS_HOST;

    location /.well-known/acme-challenge/ {
        root $CERTBOT_WEBROOT;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}
EOF

    nginx -t

    systemctl enable nginx
    systemctl restart nginx
}


setup_tls() {
    echo "========================================"
    echo "SETTING UP TLS"
    echo "========================================"

    certbot certonly \
        --webroot \
        --webroot-path "$CERTBOT_WEBROOT" \
        --non-interactive \
        --agree-tos \
        --no-eff-email \
        --email "admin@${DOMAIN}" \
        --cert-name sys-monitor \
        -d "$GRAFANA_HOST" \
        -d "$PROM_HOST" \
        -d "$GITHUB_HOST" \
        -d "$CODEBASE_HOST" \
        -d "$GITOPS_HOST"

    cat > "$NGINX_CONF" <<EOF
server {
    listen 80;
    listen [::]:80;

    server_name \
        $GRAFANA_HOST \
        $PROM_HOST \
        $GITHUB_HOST \
        $CODEBASE_HOST \
        $GITOPS_HOST;

    location /.well-known/acme-challenge/ {
        root $CERTBOT_WEBROOT;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;

    server_name $GRAFANA_HOST;

    ssl_certificate /etc/letsencrypt/live/sys-monitor/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/sys-monitor/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:3001;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;

    server_name $PROM_HOST;

    ssl_certificate /etc/letsencrypt/live/sys-monitor/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/sys-monitor/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:9090;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;

    server_name $GITHUB_HOST;

    ssl_certificate /etc/letsencrypt/live/sys-monitor/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/sys-monitor/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:3000;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;

    server_name $CODEBASE_HOST;

    ssl_certificate /etc/letsencrypt/live/sys-monitor/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/sys-monitor/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:8080;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;

    server_name $GITOPS_HOST;

    ssl_certificate /etc/letsencrypt/live/sys-monitor/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/sys-monitor/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:9105;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }
}
EOF

    nginx -t
    systemctl reload nginx
}


setup_cert_renewal() {
    echo "========================================"
    echo "SETTING UP CERTIFICATE RENEWAL"
    echo "========================================"

    cat > /usr/local/bin/sys-monitor-nginx-reload <<'EOF'
#!/bin/bash

set -euo pipefail

nginx -t
systemctl reload nginx
EOF

    chmod 755 /usr/local/bin/sys-monitor-nginx-reload

    cat > /etc/systemd/system/sys-monitor-cert-renew.service <<'EOF'
[Unit]
Description=Renew sys-monitor Let's Encrypt certificates

[Service]
Type=oneshot
ExecStart=/usr/bin/certbot renew --quiet --deploy-hook /usr/local/bin/sys-monitor-nginx-reload
EOF

    cat > /etc/systemd/system/sys-monitor-cert-renew.timer <<'EOF'
[Unit]
Description=Renew sys-monitor TLS certificates periodically

[Timer]
OnCalendar=*-*-* 03:17:00
RandomizedDelaySec=1h
Persistent=true

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable --now sys-monitor-cert-renew.timer

    echo "Certificate renewal timer:"
    systemctl status sys-monitor-cert-renew.timer --no-pager
}
