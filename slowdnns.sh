#!/bin/bash
# ===============================================
if [ ! -e /root/subdomainx ]; then
NS_DOMAIN=$(cat /etc/xray/domain);
else
NS_DOMAIN=$(cat /root/subdomainx);
fi
GIT_CMD="https://github.com/FighterTunnel/tunnel/raw/main/"

echo $NS_DOMAIN > /root/nsdomain
echo $NS_DOMAIN > /etc/xray/dns

nameserver=$(cat /root/nsdomain)
apt update -y
apt install -y python3 python3-dnslib net-tools
apt install dnsutils -y
#apt install golang -y
apt install git -y
apt install curl -y
apt install wget -y
apt install screen -y
apt install cron -y
apt install iptables -y
apt install -y git screen whois dropbear wget
#apt install -y pwgen python php jq curl
apt install -y sudo gnutls-bin
#apt install -y mlocate dh-make libaudit-dev build-essential
apt install -y dos2unix debconf-utils
service cron reload
service cron restart

rm -rf /etc/slowdns

mkdir -p /etc/slowdns
wget -O dnstt-server "${GIT_CMD}X-SlowDNS/dnstt-server" && chmod +x dnstt-server >/dev/null 2>&1
wget -O dnstt-client "${GIT_CMD}X-SlowDNS/dnstt-client" && chmod +x dnstt-client >/dev/null 2>&1
./dnstt-server -gen-key -privkey-file server.key -pubkey-file server.pub
chmod +x *
mv * /etc/slowdns
wget -O /etc/systemd/system/client.service "${GIT_CMD}X-SlowDNS/client" >/dev/null 2>&1
wget -O /etc/systemd/system/server.service "${GIT_CMD}X-SlowDNS/server" >/dev/null 2>&1
sed -i "s/xxxx/$NS_DOMAIN/g" /etc/systemd/system/client.service 
sed -i "s/xxxx/$NS_DOMAIN/g" /etc/systemd/system/server.service
	
iptables -I INPUT -p udp --dport 5300 -j ACCEPT
iptables -t nat -I PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300
iptables-save >/etc/iptables/rules.v4 >/dev/null 2>&1
iptables-save >/etc/iptables.up.rules >/dev/null 2>&1
netfilter-persistent save >/dev/null 2>&1
netfilter-persistent reload >/dev/null 2>&1
systemctl enable iptables >/dev/null 2>&1
systemctl start iptables >/dev/null 2>&1
systemctl restart iptables >/dev/null 2>&1
