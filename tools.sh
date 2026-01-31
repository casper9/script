#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

clear
red='\e[1;31m'
green2='\e[1;32m'
yell='\e[1;33m'
NC='\e[0m'
green() { echo -e "\\033[32;1m${*}\\033[0m"; }
red() { echo -e "\\033[31;1m${*}\\033[0m"; }
yellow() { echo -e "\\033[33;1m${*}\\033[0m"; }

echo "           Tools install...!"
echo "                  Progress..."
sleep 0.3

# Fix: apt-get clean all -> clean saja
apt-get clean || true
apt-get update -y >/dev/null
apt-get autoremove -y >/dev/null || true

# Detect interface untuk vnstat (biar NET gak kosong)
NET="$(ip -o -4 route show to default 2>/dev/null | awk '{print $5}' | head -n1 || true)"
if [[ -z "${NET}" ]]; then
  NET="$(ip -o link show | awk -F': ' '{print $2}' | grep -E '^(eth|ens|enp|venet|bond|wlan)' | head -n1 || true)"
fi
[[ -z "${NET}" ]] && NET="eth0"

# ===== Install paket SEKALI (lebih cepat) =====
# Catatan:
# - squid3 sudah deprecated, pakai squid
# - python/python2 sering gak ada di Ubuntu baru -> dibuang biar gak error/lama
apt-get install -y --no-install-recommends \
  iptables iptables-persistent netfilter-persistent \
  figlet ruby libxml-parser-perl \
  squid nmap rsyslog iftop htop \
  zip unzip net-tools sed bc \
  apt-transport-https build-essential \
  neofetch lsof openssl \
  openvpn easy-rsa fail2ban tmux stunnel4 \
  socat cron bash-completion ntpdate chrony \
  speedtest-cli p7zip-full \
  python3 python3-pip \
  shc \
  nginx \
  php php-fpm php-cli \
  dropbear \
  nodejs npm \
  vnstat libsqlite3-dev \
  ca-certificates curl wget gnupg lsb-release \
  >/dev/null

# ===== vnstat (tanpa compile biar gak lama) =====
systemctl enable vnstat >/dev/null 2>&1 || true
systemctl restart vnstat >/dev/null 2>&1 || true

# Init interface vnstat (toleran)
vnstat --add -i "${NET}" >/dev/null 2>&1 || vnstat -u -i "${NET}" >/dev/null 2>&1 || true

# Set interface di vnstat.conf (kalau file ada)
if [[ -f /etc/vnstat.conf ]]; then
  if grep -qE '^[# ]*Interface' /etc/vnstat.conf; then
    sed -i "s|^[# ]*Interface.*|Interface \"${NET}\"|g" /etc/vnstat.conf
  else
    echo "Interface \"${NET}\"" >> /etc/vnstat.conf
  fi
fi

chown -R vnstat:vnstat /var/lib/vnstat 2>/dev/null || true
systemctl restart vnstat >/dev/null 2>&1 || true

# // install lolcat (tetap seperti awal, tapi jangan bikin gagal kalau link mati)
cd /root
if wget -q -O lolcat.sh https://raw.githubusercontent.com/casper9/script/main/lolcat.sh; then
  chmod +x lolcat.sh
  ./lolcat.sh || true
else
  yellow "lolcat.sh gagal didownload, skip."
fi

yellow "Dependencies successfully installed..."
sleep 0.5
clear

mkdir -p /etc/tools

green "DONE ✅"
yellow "Interface: ${NET}"
