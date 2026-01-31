#!/bin/bash
# ==========================================
# Xray Installer + Nginx WS/GRPC + HTTP Upgrade
# Bebas path semua protokol via Nginx rewrite
# NO PAUSE / NO PROMPT (non-interactive)
# Ubuntu/Debian VPS
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
  err "Run as root."
  exit 1
fi

# ===== Domain =====
mkdir -p /etc/xray
domain="casper1.dev"
if [[ -s /etc/xray/domain ]]; then
  domain="$(tr -d ' \r\n' </etc/xray/domain)"
fi
[[ -z "$domain" ]] && domain="casper1.dev"
info "Domain: $domain"

# ===== Update & packages =====
info "Updating packages..."
apt clean || true
apt update -y

info "Installing dependencies..."
apt install -y curl socat xz-utils wget apt-transport-https gnupg gnupg2 dnsutils lsb-release \
  cron bash-completion ntpdate zip pwgen openssl netcat lsof

# iptables-persistent (avoid prompts)
apt install -y iptables || true
apt install -y iptables-persistent || true

# ===== Time sync =====
info "Setting time sync..."
timedatectl set-ntp true || true
ntpdate pool.ntp.org || true
apt install -y chrony || true
systemctl enable chrony --now || true
systemctl restart chrony || true
timedatectl set-timezone Asia/Jakarta || true

# ===== nginx =====
if ! command -v nginx >/dev/null 2>&1; then
  info "Installing nginx..."
  apt install -y nginx
fi

# ===== Install Xray core =====
info "Installing Xray core..."
mkdir -p /run/xray
chown www-data:www-data /run/xray || true

mkdir -p /var/log/xray /etc/xray
chown www-data:www-data /var/log/xray || true
touch /var/log/xray/access.log /var/log/xray/error.log /var/log/xray/access2.log /var/log/xray/error2.log

latest_version="$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases \
  | grep tag_name | sed -E 's/.*"v(.*)".*/\1/' | head -n 1)"

bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" \
  @ install -u www-data --version "$latest_version" >/dev/null 2>&1 || true

if [[ ! -x /usr/local/bin/xray ]]; then
  err "xray binary not found. Install failed."
  exit 1
fi

# ===== SSL (acme.sh standalone) =====
info "Issuing SSL (standalone) ..."
systemctl stop nginx || true
lsof -t -i tcp:80 -s tcp:listen | xargs -r kill || true

mkdir -p /root/.acme.sh
curl -fsSL https://acme-install.netlify.app/acme.sh -o /root/.acme.sh/acme.sh
chmod +x /root/.acme.sh/acme.sh

/root/.acme.sh/acme.sh --upgrade --auto-upgrade
/root/.acme.sh/acme.sh --set-default-ca --server letsencrypt

# NOTE: DNS domain must point to this VPS IP
/root/.acme.sh/acme.sh --issue -d "$domain" --standalone -k ec-256
/root/.acme.sh/acme.sh --installcert -d "$domain" \
  --fullchainpath /etc/xray/xray.crt \
  --keypath /etc/xray/xray.key --ecc

# ===== Auto renew SSL =====
info "Setting SSL renew cron..."
cat >/usr/local/bin/ssl_renew.sh <<'SH'
#!/bin/bash
/etc/init.d/nginx stop || true
"/root/.acme.sh"/acme.sh --cron --home "/root/.acme.sh" &> /root/renew_ssl.log
/etc/init.d/nginx start || true
SH
chmod +x /usr/local/bin/ssl_renew.sh
( crontab -l 2>/dev/null | grep -q 'ssl_renew.sh' ) || \
  (crontab -l 2>/dev/null; echo "15 03 */3 * * /usr/local/bin/ssl_renew.sh") | crontab -

# ===== Web root =====
mkdir -p /home/vps/public_html
echo "OK" > /home/vps/public_html/index.html

# ===== UUID =====
uuid="$(cat /proc/sys/kernel/random/uuid)"
info "UUID: $uuid"

# ===== Xray config =====
info "Writing Xray config..."
cat > /etc/xray/config.json << END
{
  "log": {
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log",
    "loglevel": "info"
  },
  "inbounds": [
    {
      "listen": "127.0.0.1",
      "port": 10085,
      "protocol": "dokodemo-door",
      "settings": { "address": "127.0.0.1" },
      "tag": "api"
    },

    {
      "listen": "127.0.0.1",
      "port": 14016,
      "protocol": "vless",
      "settings": { "decryption": "none", "clients": [{ "id": "${uuid}" }] },
      "streamSettings": { "network": "ws", "wsSettings": { "path": "/vless" } }
    },
    {
      "listen": "127.0.0.1",
      "port": 23456,
      "protocol": "vmess",
      "settings": { "clients": [{ "id": "${uuid}", "alterId": 0 }] },
      "streamSettings": { "network": "ws", "wsSettings": { "path": "/vmess" } }
    },
    {
      "listen": "127.0.0.1",
      "port": 28406,
      "protocol": "vmess",
      "settings": { "clients": [{ "id": "${uuid}", "alterId": 0 }] },
      "streamSettings": { "network": "ws", "wsSettings": { "path": "/worryfree" } }
    },
    {
      "listen": "127.0.0.1",
      "port": 25432,
      "protocol": "trojan",
      "settings": { "clients": [{ "password": "${uuid}" }], "udp": true },
      "streamSettings": { "network": "ws", "wsSettings": { "path": "/trojan-ws" } }
    },
    {
      "listen": "127.0.0.1",
      "port": 30300,
      "protocol": "shadowsocks",
      "settings": { "clients": [{ "method": "aes-128-gcm", "password": "${uuid}" }], "network": "tcp,udp" },
      "streamSettings": { "network": "ws", "wsSettings": { "path": "/ss-ws" } }
    },

    {
      "listen": "127.0.0.1",
      "port": 24456,
      "protocol": "vless",
      "settings": { "decryption": "none", "clients": [{ "id": "${uuid}" }] },
      "streamSettings": { "network": "grpc", "grpcSettings": { "serviceName": "vless-grpc" } }
    },
    {
      "listen": "127.0.0.1",
      "port": 31234,
      "protocol": "vmess",
      "settings": { "clients": [{ "id": "${uuid}", "alterId": 0 }] },
      "streamSettings": { "network": "grpc", "grpcSettings": { "serviceName": "vmess-grpc" } }
    },
    {
      "listen": "127.0.0.1",
      "port": 33456,
      "protocol": "trojan",
      "settings": { "clients": [{ "password": "${uuid}" }] },
      "streamSettings": { "network": "grpc", "grpcSettings": { "serviceName": "trojan-grpc" } }
    },
    {
      "listen": "127.0.0.1",
      "port": 30310,
      "protocol": "shadowsocks",
      "settings": { "clients": [{ "method": "aes-128-gcm", "password": "${uuid}" }], "network": "tcp,udp" },
      "streamSettings": { "network": "grpc", "grpcSettings": { "serviceName": "ss-grpc" } }
    }
  ],
  "outbounds": [
    { "protocol": "freedom", "settings": {} },
    { "protocol": "blackhole", "settings": {}, "tag": "blocked" }
  ],
  "routing": {
    "rules": [
      {
        "type": "field",
        "ip": [
          "0.0.0.0/8","10.0.0.0/8","100.64.0.0/10","169.254.0.0/16","172.16.0.0/12",
          "192.0.0.0/24","192.0.2.0/24","192.168.0.0/16","198.18.0.0/15",
          "198.51.100.0/24","203.0.113.0/24","::1/128","fc00::/7","fe80::/10"
        ],
        "outboundTag": "blocked"
      },
      { "type": "field", "inboundTag": ["api"], "outboundTag": "api" },
      { "type": "field", "outboundTag": "blocked", "protocol": ["bittorrent"] }
    ]
  },
  "stats": {},
  "api": { "services": ["StatsService"], "tag": "api" },
  "policy": {
    "levels": { "0": { "statsUserDownlink": true, "statsUserUplink": true } },
    "system": {
      "statsInboundUplink": true,
      "statsInboundDownlink": true,
      "statsOutboundUplink": true,
      "statsOutboundDownlink": true
    }
  }
}
END

# ===== systemd =====
info "Writing systemd service..."
cat >/etc/systemd/system/xray.service <<'EOF'
[Unit]
Description=Xray Service
Documentation=https://github.com/XTLS/Xray-core
After=network.target nss-lookup.target

[Service]
User=www-data
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -config /etc/xray/config.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

cat >/etc/systemd/system/runn.service <<'EOF'
[Unit]
Description=casper
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/bin/mkdir -p /var/run/xray
ExecStart=/usr/bin/chown www-data:www-data /var/run/xray
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# ===== Nginx config (HTTP Upgrade + bebas path WS & gRPC) =====
info "Writing nginx xray.conf..."
cat >/etc/nginx/conf.d/xray.conf <<EOF
# WebSocket upgrade helper
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

  root /home/vps/public_html;

  location / {
    try_files \$uri \$uri/ =404;
  }

  # ========== WS fixed (asli) ==========
  location = /vless {
    proxy_pass http://127.0.0.1:14016;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection \$connection_upgrade;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
  }
  location = /vmess {
    proxy_pass http://127.0.0.1:23456;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection \$connection_upgrade;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
  }
  location = /worryfree {
    proxy_pass http://127.0.0.1:28406;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection \$connection_upgrade;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
  }
  location = /trojan-ws {
    proxy_pass http://127.0.0.1:25432;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection \$connection_upgrade;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
  }
  location = /ss-ws {
    proxy_pass http://127.0.0.1:30300;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection \$connection_upgrade;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
  }

  # ========== WS bebas path (prefix) ==========
  location ^~ /vless/     { rewrite ^/vless/.*\$     /vless break;     proxy_pass http://127.0.0.1:14016; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$connection_upgrade; proxy_set_header Host \$host; proxy_set_header X-Real-IP \$remote_addr; proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for; }
  location ^~ /vmess/     { rewrite ^/vmess/.*\$     /vmess break;     proxy_pass http://127.0.0.1:23456; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$connection_upgrade; proxy_set_header Host \$host; proxy_set_header X-Real-IP \$remote_addr; proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for; }
  location ^~ /worryfree/ { rewrite ^/worryfree/.*\$ /worryfree break; proxy_pass http://127.0.0.1:28406; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$connection_upgrade; proxy_set_header Host \$host; proxy_set_header X-Real-IP \$remote_addr; proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for; }
  location ^~ /trojan/    { rewrite ^/trojan/.*\$    /trojan-ws break; proxy_pass http://127.0.0.1:25432; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$connection_upgrade; proxy_set_header Host \$host; proxy_set_header X-Real-IP \$remote_addr; proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for; }
  location ^~ /ss/        { rewrite ^/ss/.*\$        /ss-ws break;     proxy_pass http://127.0.0.1:30300; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$connection_upgrade; proxy_set_header Host \$host; proxy_set_header X-Real-IP \$remote_addr; proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for; }

  # ========== gRPC fixed ==========
  location ^~ /vless-grpc  { grpc_set_header Host \$host; grpc_pass grpc://127.0.0.1:24456; }
  location ^~ /vmess-grpc  { grpc_set_header Host \$host; grpc_pass grpc://127.0.0.1:31234; }
  location ^~ /trojan-grpc { grpc_set_header Host \$host; grpc_pass grpc://127.0.0.1:33456; }
  location ^~ /ss-grpc     { grpc_set_header Host \$host; grpc_pass grpc://127.0.0.1:30310; }

  # ========== gRPC bebas path ==========
  location ^~ /grpc/vless/  { rewrite ^/grpc/vless/.*\$  /vless-grpc break;  grpc_set_header Host \$host; grpc_pass grpc://127.0.0.1:24456; }
  location ^~ /grpc/vmess/  { rewrite ^/grpc/vmess/.*\$  /vmess-grpc break;  grpc_set_header Host \$host; grpc_pass grpc://127.0.0.1:31234; }
  location ^~ /grpc/trojan/ { rewrite ^/grpc/trojan/.*\$ /trojan-grpc break; grpc_set_header Host \$host; grpc_pass grpc://127.0.0.1:33456; }
  location ^~ /grpc/ss/     { rewrite ^/grpc/ss/.*\$     /ss-grpc break;     grpc_set_header Host \$host; grpc_pass grpc://127.0.0.1:30310; }
}
EOF

# ===== Start services =====
info "Restarting services..."
systemctl daemon-reload
systemctl enable runn --now || true
systemctl enable xray --now || true
systemctl restart runn || true
systemctl restart xray || true

nginx -t
systemctl enable nginx --now || true
systemctl restart nginx || true

# ===== Self-check =====
info "Self-check..."
systemctl is-active xray >/dev/null && info "xray: active" || warn "xray: NOT active"
systemctl is-active nginx >/dev/null && info "nginx: active" || warn "nginx: NOT active"

echo ""
info "DONE ✅"
echo "DOMAIN : $domain"
echo "UUID   : $uuid"
echo ""
echo "WS fixed path: /vless /vmess /worryfree /trojan-ws /ss-ws"
echo "WS bebas     : /vless/xxx /vmess/xxx /worryfree/xxx /trojan/xxx /ss/xxx"
echo "gRPC fixed   : /vless-grpc /vmess-grpc /trojan-grpc /ss-grpc"
echo "gRPC bebas   : /grpc/vless/xxx /grpc/vmess/xxx /grpc/trojan/xxx /grpc/ss/xxx"
echo ""
