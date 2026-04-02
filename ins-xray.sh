#!/bin/bash
# ==========================================
# Xray Installer + Nginx WS/GRPC + HTTP Upgrade
# Modifed: Always Clean Download & Smart SSL
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

uuid=$(cat /proc/sys/kernel/random/uuid)

# ===== Update & Packages =====
info "Updating packages..."
apt update -y
apt install -y curl socat xz-utils wget gnupg2 dnsutils lsb-release \
  cron bash-completion ntpdate zip pwgen openssl netcat lsof nginx chrony \
  iptables iptables-persistent

# ===== Time Sync =====
timedatectl set-ntp true || true
timedatectl set-timezone Asia/Jakarta || true
systemctl enable --now chrony

# ===== Xray Core Installation =====
info "Installing Xray core..."
mkdir -p /var/log/xray /etc/xray /run/xray
chown -R www-data:www-data /var/log/xray /run/xray

# Selalu ambil versi terbaru
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

# Set default CA ke LetsEncrypt
/root/.acme.sh/acme.sh --upgrade --auto-upgrade
/root/.acme.sh/acme.sh --set-default-ca --server letsencrypt

if [[ -f /etc/xray/xray.crt && -f /etc/xray/xray.key ]]; then
    warn "SSL Certificate sudah ada. Melewati proses issue (Skip)."
else
    info "Issuing SSL Certificate (Standalone)..."
    systemctl stop nginx || true
    lsof -t -i tcp:80 | xargs -r kill || true
    
    /root/.acme.sh/acme.sh --issue -d "$domain" --standalone -k ec-256 --force
    /root/.acme.sh/acme.sh --installcert -d "$domain" \
      --fullchainpath /etc/xray/xray.crt \
      --keypath /etc/xray/xray.key --ecc
    systemctl start nginx || true
fi

# ===== Xray Config & Systemd =====
# (Config JSON tetap sama seperti versi kamu karena sudah benar)
# Pastikan path log di chmod lagi untuk berjaga-jaga
touch /var/log/xray/access.log /var/log/xray/error.log
chown -R www-data:www-data /var/log/xray

# --- Bagian penulisan /etc/xray/config.json kamu di sini ---
# (Gunakan blok cat > /etc/xray/config.json dari script asli kamu)

# ===== Nginx Configuration =====
info "Konfigurasi Nginx Xray..."
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
  ssl_ciphers         ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256;

  root /home/vps/public_html;

  # WS Fixed Path
  location /vless {
    proxy_redirect off;
    proxy_pass http://127.0.0.1:14016;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection \$connection_upgrade;
    proxy_set_header Host \$host;
  }

  location /vmess {
    proxy_redirect off;
    proxy_pass http://127.0.0.1:23456;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection \$connection_upgrade;
    proxy_set_header Host \$host;
  }

  # gRPC Fixed Path
  location ^~ /vless-grpc {
    proxy_redirect off;
    grpc_set_header Host \$host;
    grpc_set_header X-Real-IP \$remote_addr;
    grpc_pass grpc://127.0.0.1:24456;
  }
  
  # (Tambahkan path lainnya sesuai script kamu)
}
EOF

# ===== Restart & Clean Up =====
info "Restarting Services..."
systemctl daemon-reload
systemctl enable xray nginx
systemctl restart xray nginx

info "DONE ✅"
echo "DOMAIN : $domain"
echo "UUID   : $uuid"
