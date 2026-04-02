#!/bin/bash
# Hapus -e agar script tidak berhenti tiba-tiba jika ada error kecil
set -uo pipefail
export DEBIAN_FRONTEND=noninteractive

clear
red='\e[1;31m'
green2='\e[1;32m'
yell='\e[1;33m'
NC='\e[0m'

green() { echo -e "\\033[32;1m${*}\\033[0m"; }
red() { echo -e "\\033[31;1m${*}\\033[0m"; }
yellow() { echo -e "\\033[33;1m${*}\\033[0m"; }

echo -e "${green2}======================================${NC}"
echo -e "${green2}       Starting Tools Installation    ${NC}"
echo -e "${green2}======================================${NC}"
sleep 1

# 1. Update Repositori
yellow "Step 1: Updating system repositories..."
apt-get clean
apt-get update -y
apt-get autoremove -y
echo -e "${green2}Update complete!${NC}\n"

# 2. Deteksi Interface
yellow "Step 2: Detecting network interface..."
NET="$(ip -o -4 route show to default 2>/dev/null | awk '{print $5}' | head -n1 || true)"
if [[ -z "${NET}" ]]; then
  NET="$(ip -o link show | awk -F': ' '{print $2}' | grep -E '^(eth|ens|enp|venet|bond|wlan)' | head -n1 || true)"
fi
[[ -z "${NET}" ]] && NET="eth0"
echo -e "${green2}Interface detected: ${NET}${NC}\n"

# 3. Instalasi Paket Utama (Dibuat terlihat outputnya)
yellow "Step 3: Installing dependencies (this may take a while)..."
# Menggunakan --force-confold agar tidak berhenti jika ada konflik config file
apt-get install -y -o Dpkg::Options::="--force-confold" --no-install-recommends \
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
  ca-certificates curl wget gnupg lsb-release

echo -e "\n${green2}All packages installed successfully!${NC}\n"

# 4. Konfigurasi vnstat
yellow "Step 4: Configuring vnstat..."
systemctl enable vnstat >/dev/null 2>&1
systemctl restart vnstat >/dev/null 2>&1
vnstat --add -i "${NET}" >/dev/null 2>&1 || vnstat -u -i "${NET}" >/dev/null 2>&1 || true

if [[ -f /etc/vnstat.conf ]]; then
  sed -i "s|^[# ]*Interface.*|Interface \"${NET}\"|g" /etc/vnstat.conf
fi
chown -R vnstat:vnstat /var/lib/vnstat 2>/dev/null || true
systemctl restart vnstat >/dev/null 2>&1
echo -e "${green2}vnstat configured!${NC}\n"

# 5. Install Lolcat
yellow "Step 5: Installing additional components..."
cd /root
if wget -q -O lolcat.sh https://raw.githubusercontent.com/casper9/script/main/lolcat.sh; then
  chmod +x lolcat.sh
  ./lolcat.sh || true
else
  red "Warning: lolcat.sh download failed, skipping."
fi

# 6. Finalisasi
mkdir -p /etc/tools
clear
echo -e "${green2}======================================${NC}"
echo -e "${green2}      INSTALLATION COMPLETED ✅       ${NC}"
echo -e "${green2}======================================${NC}"
echo -e "${yell}Interface   : ${NET}${NC}"
echo -e "${yell}Status      : Success${NC}"
echo -e "${green2}======================================${NC}"
