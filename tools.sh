#!/bin/bash
clear
red='\e[1;31m'
green2='\e[1;32m'
yell='\e[1;33m'
NC='\e[0m'
green() { echo -e "\\033[32;1m${*}\\033[0m"; }
red() { echo -e "\\033[31;1m${*}\\033[0m"; }


echo "           Tools install...!"
echo "                  Progress..."
sleep 0.5
sudo apt-get clean all
apt-get autoremove -y
apt-get -y install iptables iptables-persistent netfilter-persistent figlet ruby libxml-parser-perl squid nmap rsyslog iftop htop zip unzip net-tools sed bc apt-transport-https build-essential libxml-parser-perl neofetch lsof openssl openvpn easy-rsa fail2ban tmux stunnel4 squid3 socat cron bash-completion ntpdate apt-transport-https chrony speedtest-cli p7zip-full python python3 python3-pip shc nodejs nginx php php-cli dropbear

wget -O requirements.txt https://raw.githubusercontent.com/casper9/script/main/requirements.txt
pip3 install -r requirements.txt

sudo apt-get -y install vnstat
/etc/init.d/vnstat restart
sudo apt-get -y install libsqlite3-dev
wget https://raw.githubusercontent.com/casper9/script/main/vnstat-2.6.tar.gz
tar zxvf vnstat-2.6.tar.gz
cd vnstat-2.6
./configure --prefix=/usr --sysconfdir=/etc && make && make install
cd
vnstat -u -i $NET
sed -i 's/Interface "'""eth0""'"/Interface "'""$NET""'"/g' /etc/vnstat.conf
chown vnstat:vnstat /var/lib/vnstat -R
systemctl enable vnstat
/etc/init.d/vnstat restart
rm -f /root/vnstat-2.6.tar.gz
rm -rf /root/vnstat-2.6

yellow() { echo -e "\\033[33;1m${*}\\033[0m"; }
yellow "Dependencies successfully installed..."
sleep 1
clear

mkdir -p /etc/tools
