#!/usr/bin/env bash
set -Eeuo pipefail

# ==========================================
# CLEAN SSH/VPN INSTALLER (ID)
# - Skip otomatis kalau file/komponen sudah ada
# - Auto-check UDP/TUN support
# - Hindari prompt "replace? y/n" dari vpn.zip (skip bila OpenVPN sudah terpasang)
# - Download aman: tulis ke /tmp dulu lalu mv (hindari curl error 23 karena direct write)
# ==========================================

BASE="https://raw.githubusercontent.com/casper9/script/main"

# detail cert (stunnel self-signed)
country=ID
state=Indonesia
locality=Jakarta
organization=none
organizationalunit=none
commonname=none
email=none

log(){  echo -e "\033[1;36m[INFO]\033[0m $*"; }
ok(){   echo -e "\033[1;32m[OK]\033[0m   $*"; }
warn(){ echo -e "\033[1;33m[WARN]\033[0m $*"; }
die(){  echo -e "\033[1;31m[ERR]\033[0m  $*" >&2; exit 1; }

need_root(){ [[ "${EUID}" -eq 0 ]] || die "Jalankan sebagai root"; }

# FORCE=1 untuk paksa overwrite / reinstall
FORCE="${FORCE:-0}"

# download file: kalau sudah ada & FORCE=0 -> skip
download(){
  local url="$1" out="$2"
  local dir tmp

  dir="$(dirname "$out")"
  mkdir -p "$dir"

  if [[ "$FORCE" != "1" && -s "$out" ]]; then
    log "Skip download (sudah ada): $out"
    return 0
  fi

  tmp="/tmp/$(basename "$out").$$.tmp"
  rm -f "$tmp" 2>/dev/null || true

  # pakai curl ke tmp dulu, baru mv (lebih aman daripada langsung ke /usr/sbin dll)
  curl -fsSL "$url" -o "$tmp" || { rm -f "$tmp" || true; die "Gagal download: $url"; }

  chmod +x "$tmp" 2>/dev/null || true
  mv -f "$tmp" "$out"
  ok "Downloaded: $out"
}

php_pool_file(){
  local f
  f="$(ls -1 /etc/php/*/fpm/pool.d/www.conf 2>/dev/null | head -n 1 || true)"
  [[ -n "$f" ]] || die "php-fpm pool www.conf tidak ditemukan"
  echo "$f"
}

apt_prepare(){
  export DEBIAN_FRONTEND=noninteractive
  log "Install dependency..."
  apt-get update -y

  apt-get install -y \
    curl wget unzip zip git jq ca-certificates gnupg lsb-release \
    nginx php-fpm \
    dropbear stunnel4 openssl \
    iptables iptables-persistent netfilter-persistent \
    cron p7zip-full bc lsof \
    socat xz-utils dnsutils \
    pwgen netcat-openbsd

  ok "Dependency siap"
}

# =========================
# AUTO CHECK UDP SUPPORT
# =========================
udp_support_check(){
  log "Cek dukungan UDP/TUN di VPS..."

  if [[ ! -c /dev/net/tun ]]; then
    warn "/dev/net/tun tidak ada. Coba buat..."
    mkdir -p /dev/net || true
    mknod /dev/net/tun c 10 200 2>/dev/null || true
    chmod 600 /dev/net/tun 2>/dev/null || true
  fi

  if [[ ! -c /dev/net/tun ]]; then
    warn "TUN tidak tersedia. UDP Custom kemungkinan gagal."
    return 1
  fi

  if ! iptables -t mangle -L >/dev/null 2>&1; then
    warn "iptables mangle tidak tersedia. UDP Custom kemungkinan gagal."
    return 1
  fi

  ok "UDP/TUN terlihat OK."
  return 0
}

apply_password_policy(){
  log "Apply PAM password policy (optional)..."
  if curl -fsSL "${BASE}/password" >/dev/null 2>&1; then
    # skip kalau sudah ada & FORCE=0
    if [[ "$FORCE" != "1" && -s /etc/pam.d/common-password ]]; then
      log "Skip apply common-password (sudah ada)"
      return 0
    fi
    curl -fsSL "${BASE}/password" \
      | openssl aes-256-cbc -d -a -pass pass:scvps07gg -pbkdf2 \
      > /etc/pam.d/common-password || warn "Gagal apply common-password (skip)"
    ok "common-password updated"
  else
    warn "File password policy tidak ada (skip)"
  fi
}

setup_nginx_php(){
  log "Setup nginx + php-fpm..."

  rm -f /etc/nginx/sites-enabled/default /etc/nginx/sites-available/default || true

  download "${BASE}/nginx.conf" /etc/nginx/nginx.conf
  mkdir -p /etc/nginx/conf.d
  download "${BASE}/vps.conf" /etc/nginx/conf.d/vps.conf

  local pool
  pool="$(php_pool_file)"
  sed -i 's|^listen\s*=.*|listen = 127.0.0.1:9000|g' "$pool"

  id vps >/dev/null 2>&1 || useradd -m vps || true
  mkdir -p /home/vps/public_html

  # index.html: skip bila sudah ada
  if [[ "$FORCE" == "1" || ! -s /home/vps/public_html/index.html ]]; then
    download "${BASE}/index.html" /home/vps/public_html/index.html
  else
    log "Skip index.html (sudah ada)"
  fi

  if [[ "$FORCE" == "1" || ! -s /home/vps/public_html/info.php ]]; then
    echo "<?php phpinfo(); ?>" > /home/vps/public_html/info.php
  fi

  chown -R www-data:www-data /home/vps/public_html
  chmod -R g+rw /home/vps/public_html

  # restart php-fpm versi yang ada (tanpa wildcard)
  systemctl restart php8.3-fpm 2>/dev/null || \
  systemctl restart php8.2-fpm 2>/dev/null || \
  systemctl restart php8.1-fpm 2>/dev/null || true

  systemctl restart nginx || true
  ok "nginx+php siap"
}

setup_badvpn(){
  log "Install badvpn..."

  # jika badvpn sudah ada & FORCE=0 -> skip
  if [[ "$FORCE" != "1" && -s /usr/sbin/badvpn ]]; then
    log "Skip badvpn binary (sudah ada)"
  else
    download "${BASE}/badvpn" /usr/sbin/badvpn
    chmod +x /usr/sbin/badvpn || true
  fi

  # service files
  download "${BASE}/badvpn1.service" /etc/systemd/system/badvpn1.service
  download "${BASE}/badvpn2.service" /etc/systemd/system/badvpn2.service
  download "${BASE}/badvpn3.service" /etc/systemd/system/badvpn3.service

  systemctl daemon-reload
  for s in badvpn1 badvpn2 badvpn3; do
    systemctl enable "$s" >/dev/null 2>&1 || true
    systemctl restart "$s" >/dev/null 2>&1 || true
  done
  ok "badvpn jalan"
}

setup_ssh_ports(){
  log "Setting SSH ports..."
  sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication yes/g' /etc/ssh/sshd_config || true
  sed -i 's/^#\?AcceptEnv/##AcceptEnv/g' /etc/ssh/sshd_config || true

  for p in 22 53 500 40000 51443 58080; do
    grep -qE "^Port ${p}$" /etc/ssh/sshd_config || echo "Port ${p}" >> /etc/ssh/sshd_config
  done

  systemctl restart ssh 2>/dev/null || service ssh restart || true
  ok "sshd OK"
}

setup_dropbear(){
  log "Setup dropbear..."
  sed -i 's/^NO_START=.*/NO_START=0/g' /etc/default/dropbear || true
  sed -i 's/^DROPBEAR_PORT=.*/DROPBEAR_PORT=143/g' /etc/default/dropbear || true
  sed -i '/^DROPBEAR_EXTRA_ARGS=/d' /etc/default/dropbear || true
  echo 'DROPBEAR_EXTRA_ARGS="-p 50000 -p 109 -p 110 -p 69"' >> /etc/default/dropbear

  grep -q "/bin/false" /etc/shells || echo "/bin/false" >> /etc/shells
  grep -q "/usr/sbin/nologin" /etc/shells || echo "/usr/sbin/nologin" >> /etc/shells

  systemctl restart dropbear 2>/dev/null || service dropbear restart || true
  ok "dropbear OK"
}

setup_stunnel(){
  log "Setup stunnel..."
  mkdir -p /etc/stunnel

  # kalau config sudah ada & FORCE=0 -> jangan overwrite
  if [[ "$FORCE" != "1" && -s /etc/stunnel/stunnel.conf && -s /etc/stunnel/stunnel.pem ]]; then
    log "Skip stunnel config (sudah ada)"
  else
    cat > /etc/stunnel/stunnel.conf <<EOF
cert = /etc/stunnel/stunnel.pem
client = no
socket = a:SO_REUSEADDR=1
socket = l:TCP_NODELAY=1
socket = r:TCP_NODELAY=1

[dropbear_22]
accept = 8880
connect = 127.0.0.1:22

[dropbear_109]
accept = 8443
connect = 127.0.0.1:109

[ws-stunnel]
accept = 444
connect = 700

[openvpn]
accept = 990
connect = 127.0.0.1:1194
EOF

    openssl genrsa -out /root/key.pem 2048
    openssl req -new -x509 -key /root/key.pem -out /root/cert.pem -days 1095 \
      -subj "/C=$country/ST=$state/L=$locality/O=$organization/OU=$organizationalunit/CN=$commonname/emailAddress=$email"
    cat /root/key.pem /root/cert.pem > /etc/stunnel/stunnel.pem
  fi

  sed -i 's/^ENABLED=.*/ENABLED=1/g' /etc/default/stunnel4 || true
  systemctl restart stunnel4 2>/dev/null || service stunnel4 restart || true
  ok "stunnel OK"
}

run_remote_script(){
  local name="$1"
  log "Run ${name}..."

  # download script ke /root, skip kalau sudah ada dan FORCE=0
  if [[ "$FORCE" != "1" && -s "/root/${name}" ]]; then
    log "Skip download script (sudah ada): /root/${name}"
  else
    download "${BASE}/${name}" "/root/${name}"
    chmod +x "/root/${name}" 2>/dev/null || true
  fi

  # penting: matikan STDIN biar gak nge-freeze kalau script interaktif
  timeout 3600 bash "/root/${name}" </dev/null || warn "${name} timeout/gagal (skip)"
}

# =========================
# SKIP OPENVPN INSTALL kalau sudah ada
# (ini mencegah prompt unzip vpn.zip)
# =========================
openvpn_installed(){
  [[ -f /etc/openvpn/server.conf ]] || [[ -d /etc/openvpn/server ]] || systemctl list-unit-files | grep -qi openvpn@ || false
}

install_openvpn_slowdns_udp(){
  # OpenVPN
  if [[ "$FORCE" == "1" ]]; then
    run_remote_script "vpn.sh"
  else
    if openvpn_installed; then
      log "OpenVPN sudah terpasang -> SKIP vpn.sh (biar gak mentok vpn.zip)"
    else
      run_remote_script "vpn.sh"
    fi
  fi

  # SlowDNS (skip bila sudah ada binary/config umum)
  if [[ "$FORCE" != "1" && ( -f /etc/slowdns/server.key || -f /usr/bin/slowdns || -f /usr/local/bin/slowdns ) ]]; then
    log "SlowDNS terdeteksi -> skip slowdns.sh"
  else
    run_remote_script "slowdns.sh" || warn "slowdns gagal/skip"
  fi

  # UDP Custom (auto-check)
  if udp_support_check; then
    if [[ "$FORCE" != "1" && ( -f /etc/udp/udp.conf || -f /usr/bin/udp-custom || -f /usr/local/bin/udp-custom ) ]]; then
      log "UDP Custom terdeteksi -> skip udp-custom.sh"
    else
      run_remote_script "udp-custom.sh"
      ok "udp-custom OK"
    fi
  else
    warn "udp-custom SKIP (VPS tidak support UDP/TUN)"
  fi
}

setup_swap(){
  log "Setup swap 10GB (jika belum ada)..."
  if swapon --show | grep -q "/swapfile"; then
    ok "Swap sudah ada"
    return
  fi
  fallocate -l 10G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=10240
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null
  swapon /swapfile
  grep -q "^/swapfile" /etc/fstab || echo "/swapfile swap swap defaults 0 0" >> /etc/fstab
  ok "Swap OK"
}

install_ddos_deflate(){
  log "Install DDOS-Deflate (optional)..."
  if [[ -d /usr/local/ddos && "$FORCE" != "1" ]]; then
    warn "DDOS-Deflate sudah ada, skip"
    return
  fi
  mkdir -p /usr/local/ddos
  wget -q -O /usr/local/ddos/ddos.conf http://www.inetbase.com/scripts/ddos/ddos.conf || true
  wget -q -O /usr/local/ddos/LICENSE http://www.inetbase.com/scripts/ddos/LICENSE || true
  wget -q -O /usr/local/ddos/ignore.ip.list http://www.inetbase.com/scripts/ddos/ignore.ip.list || true
  wget -q -O /usr/local/ddos/ddos.sh http://www.inetbase.com/scripts/ddos/ddos.sh || true
  chmod 0755 /usr/local/ddos/ddos.sh || true
  ln -sf /usr/local/ddos/ddos.sh /usr/local/sbin/ddos || true
  /usr/local/ddos/ddos.sh --cron >/dev/null 2>&1 || true
  ok "DDOS-Deflate OK"
}

setup_banner(){
  log "Setup banner..."
  grep -q "^Banner /etc/issue.net" /etc/ssh/sshd_config || echo "Banner /etc/issue.net" >>/etc/ssh/sshd_config
  sed -i 's@^DROPBEAR_BANNER=.*@DROPBEAR_BANNER="/etc/issue.net"@g' /etc/default/dropbear || true

  # issue.net
  if [[ "$FORCE" == "1" || ! -s /etc/issue.net ]]; then
    download "${BASE}/issue.net" /etc/issue.net
  else
    log "Skip /etc/issue.net (sudah ada)"
  fi

  systemctl restart ssh 2>/dev/null || true
  systemctl restart dropbear 2>/dev/null || true
  ok "Banner OK"
}

run_bbr(){
  log "Install BBR (optional)..."
  if [[ "$FORCE" != "1" && ( -f /etc/sysctl.d/99-bbr.conf || grep -q "tcp_congestion_control=bbr" /etc/sysctl.conf 2>/dev/null ) ]]; then
    log "BBR sudah terdeteksi -> skip bbr.sh"
    return
  fi
  run_remote_script "bbr.sh" || warn "BBR gagal/skip"
}

block_torrent(){
  log "Block torrent..."
  local s
  for s in get_peers announce_peer find_node "BitTorrent" "BitTorrent protocol" peer_id= .torrent "announce.php?passkey=" torrent announce info_hash; do
    iptables -C FORWARD -m string --algo bm --string "$s" -j DROP 2>/dev/null || \
      iptables -A FORWARD -m string --algo bm --string "$s" -j DROP
  done

  iptables-save > /etc/iptables.up.rules
  iptables-restore < /etc/iptables.up.rules

  systemctl enable netfilter-persistent >/dev/null 2>&1 || true
  systemctl restart netfilter-persistent >/dev/null 2>&1 || true
  ok "iptables OK"
}

download_tools(){
  log "Download tools..."
  download "${BASE}/issue.net" /usr/bin/issue
  download "${BASE}/speedtest_cli.py" /usr/bin/speedtest
  download "${BASE}/xp.sh" /usr/bin/xp
  chmod +x /usr/bin/issue /usr/bin/speedtest /usr/bin/xp
  ok "tools OK"
}

setup_cron(){
  log "Setup cron..."
  cat > /etc/cron.d/xp_otm <<'EOF'
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
0 0 * * * root /usr/bin/xp
EOF

  cat > /etc/cron.d/bckp_otm <<'EOF'
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
10 */4 * * * root /usr/bin/bottelegram
EOF

  cat > /etc/cron.d/tendang <<'EOF'
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
*/13 * * * * root /usr/bin/tendang
EOF

  cat > /etc/cron.d/xraylimit <<'EOF'
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
*/15 * * * * root /usr/bin/xraylimit
EOF

  cat > /etc/cron.d/autocpu <<'EOF'
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
*/20 * * * * root /usr/bin/autocpu
EOF

  systemctl restart cron 2>/dev/null || service cron restart || true
  ok "cron OK"
}

cleanup(){
  rm -f /root/key.pem /root/cert.pem /root/bbr.sh /root/ssh-vpn.sh 2>/dev/null || true
  rm -rf /etc/apache2 2>/dev/null || true
  chown -R www-data:www-data /home/vps/public_html 2>/dev/null || true
}

main(){
  need_root
  apt_prepare

  # optional
  apply_password_policy

  setup_nginx_php
  setup_badvpn
  setup_ssh_ports
  setup_dropbear
  setup_stunnel

  install_openvpn_slowdns_udp
  setup_swap
  install_ddos_deflate
  setup_banner
  run_bbr
  block_torrent
  download_tools
  setup_cron
  cleanup

  clear
  ok "SELESAI. Reboot disarankan: reboot"
  log "Kalau mau paksa reinstall: FORCE=1 bash installer.sh"
}

main "$@"
```0
