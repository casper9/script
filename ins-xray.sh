#!/bin/bash
# ==========================================
# Xray Installer + Nginx WS/GRPC + HTTP Upgrade
# Modifed: Always Clean Download & Smart SSL
# Fix: Error 405 Method Not Allowed
# ==========================================
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# ===== Colors =====
RED='\033[0;31m'
NC='\033[0m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'

info(){ echo -e "[ ${GREEN}INFO${NC} ] $*"; }
warn(){ echo -e "[ ${ORANGE}WARN${NC} ] $*"; }
err(){  echo -e "[ ${RED}ERROR${NC} ] $*"; }

if [[ $EUID -ne 0 ]]; then
  err "Jalankan sebagai root."
  exit 1
fi

# ===== Domain & UUID =====
mkdir -p /etc/xray
domain="casper1.dev"
if [[ -f /etc/xray/domain ]]; then
  domain="$(tr -d ' \r\n' </etc/xray/domain)"
fi
info "Domain: $domain"

# Generate UUID baru setiap install atau gunakan yang lama jika ada
uuid=$(cat /proc/sys/kernel/random/uuid)

# ===== Update & Packages =====
info "Updating packages..."
apt update -y
apt install -y curl socat xz-utils wget gnupg2 dnsutils lsb-release \
  cron bash-completion ntpdate zip pwgen openssl netcat lsof nginx chrony \
  iptables iptables-persistent

# ===== Time Sync =====
info "Setting Timezone & Sync..."
timedatectl set-ntp true || true
timedatectl set-timezone Asia/Jakarta || true
systemctl enable --now chrony

# ===== Xray Core Installation =====
info "Installing Xray core..."
mkdir -p /var/log/xray /etc/xray /run/xray
chown -R www-data:www-data /var/log/xray /run/xray
touch /var/log/xray/access.log /var/log/xray/error.log
chown www-data:www-data /var/log/xray/*.log

latest_version="$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases | grep tag_name | sed -E 's/.*"v(.*)".*/\1/' | head -n 1)"

bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" \
  @ install -u www-data --version "$latest_version" >/dev/null 2>&1 || true

# ===== SSL Handling (Smart Mode) =====
info "Checking SSL Certificate..."
mkdir -p /root/.acme.sh

if [[ ! -f /root/.acme.sh/acme.sh ]]; then
    curl -fsSL https://acme-install.netlify.app/acme.sh -o /root/.acme.sh/acme.sh
    chmod +x /root/.acme.sh/acme.sh
fi

/root/.acme.sh/acme.sh --upgrade --auto-upgrade
/root/.acme.sh/acme.sh --set-default-ca --server letsencrypt

# Jika cert belum ada atau sudah expired, kita paksa renew
if [[ ! -f /etc/xray/xray.crt ]]; then
    info "Issuing SSL Certificate (Standalone)..."
    systemctl stop nginx || true
    lsof -t -i tcp:80 | xargs -r kill || true
    
    /root/.acme.sh/acme.sh --issue -d "$domain" --standalone -k ec-256 --force
    /root/.acme.sh/acme.sh --installcert -d "$domain" \
      --fullchainpath /etc/xray/xray.crt \
      --keypath /etc/xray/xray.key --ecc
else
    warn "SSL Certificate detected. Skipping issue to avoid Rate Limit."
fi

# ===== Xray Config =====
info "Writing Xray config.json..."
cat > /etc/xray/config.json << END
{
  "log": {
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log",
    "loglevel": "info"
  },
  "inbounds": [
    { "listen": "127.0.0.1", "port": 10085, "protocol": "dokodemo-door", "settings": { "address": "127.0.0.1" }, "tag": "api" },
    { "listen": "127.0.0.1", "port": 14016, "protocol": "vless", "settings": { "decryption": "none", "clients": [{ "id": "${uuid}" }] }, "streamSettings": { "network": "ws", "wsSettings": { "path": "/vless" } } },
    { "listen": "127.0.0.1", "port": 23456, "protocol": "vmess", "settings": { "clients": [{ "id": "${uuid}", "alterId": 0 }] }, "streamSettings": { "network": "ws", "wsSettings": { "path": "/vmess" } } },
    { "listen": "127.0.0.1", "port": 25432, "protocol": "trojan", "settings": { "clients": [{ "password": "${uuid}" }], "udp": true }, "streamSettings": { "network": "ws", "wsSettings": { "path": "/trojan-ws" } } },
    { "listen": "127.0.0.1", "port": 24456, "protocol": "vless", "settings": { "decryption": "none", "clients": [{ "id": "${uuid}" }] }, "streamSettings": { "network": "grpc", "grpcSettings": { "serviceName": "vless-grpc" } } },
    { "listen": "127.0.0.1", "port": 31234, "protocol": "vmess", "settings": { "clients": [{ "id": "${uuid}", "alterId": 0 }] }, "streamSettings": { "network": "grpc", "grpcSettings": { "serviceName": "vmess-grpc" } } }
  ],
  "outbounds": [
    { "protocol": "freedom", "settings": {} },
    { "protocol": "blackhole", "settings": {}, "tag": "blocked" }
  ],
  "routing": {
    "rules": [
      { "type": "field", "ip": ["0.0.0.0/8","10.0.0.0/8","127.0.0.0/8","169.254.0.0/16","172.16.0.0/12","192.168.0.0/16"], "outboundTag": "blocked" },
      { "type": "field", "outboundTag": "blocked", "protocol": ["bittorrent"] }
    ]
  }
}
END

# ===== Nginx Configuration (The Fix) =====
info "Configuring Nginx..."
cat >/etc/nginx/conf.d/xray.conf <<EOF
map \$http_upgrade \$connection_upgrade {
  default upgrade;
  ''      close;
}

server {
  listen 80;
  listen [::]:80;
  listen 443 ssl http2;
  listen [::]:443 ssl http2;
  server_name ${domain};

  ssl_certificate     /etc/xray/xray.crt;
  ssl_certificate_key /etc/xray/xray.key;
  ssl_protocols       TLSv1.2 TLSv1.3;

  root /home/vps/public_html;

  # WS Handlers
  location /vless {
    if (\$http_upgrade != "websocket") { return 404; }
    proxy_redirect off;
    proxy_pass http://127.0.0.1:14016;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection \$connection_upgrade;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
  }

  location /vmess {
    if (\$http_upgrade != "websocket") { return 404; }
    proxy_redirect off;
    proxy_pass http://127.0.0.1:23456;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection \$connection_upgrade;
    proxy_set_header Host \$host;
  }

  location /trojan-ws {
    if (\$http_upgrade != "websocket") { return 404; }
    proxy_redirect off;
    proxy_pass http://127.0.0.1:25432;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection \$connection_upgrade;
    proxy_set_header Host \$host;
  }

  # gRPC Handlers (PENTING: Gunakan grpc_pass)
  location ^~ /vless-grpc {
    proxy_redirect off;
    grpc_set_header Host \$host;
    grpc_set_header X-Real-IP \$remote_addr;
    grpc_pass grpc://127.0.0.1:24456;
  }

  location ^~ /vmess-grpc {
    proxy_redirect off;
    grpc_set_header Host \$host;
    grpc_pass grpc://127.0.0.1:31234;
  }
}
EOF

# ===== Systemd Service =====
cat >/etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service
After=network.target nss-lookup.target

[Service]
User=www-data
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -config /etc/xray/config.json
Restart=on-failure
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

# ===== Finalize =====
info "Restarting Services..."
systemctl daemon-reload
systemctl enable xray nginx
systemctl restart xray nginx

info "DONE ✅"
echo "DOMAIN : $domain"
echo "UUID   : $uuid"
echo "WS PATH: /vless, /vmess, /trojan-ws"
echo "gRPC   : vless-grpc, vmess-grpc"
