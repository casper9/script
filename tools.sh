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
apt-get -y install iptables
apt-get -y install iptables-persistent 
apt-get -y install netfilter-persistent
apt-get -y install figlet
apt-get -y install ruby 
apt-get -y install libxml-parser-perl 
apt-get -y install squid 
apt-get -y install nmap 
apt-get -y install rsyslog 
apt-get -y install iftop 
apt-get -y install htop 
apt-get -y install zip 
apt-get -y install unzip 
apt-get -y install net-tools 
apt-get -y install sed 
apt-get -y install bc 
apt-get -y install apt-transport-https
apt-get -y install build-essential 
apt-get -y install libxml-parser-perl 
apt-get -y install neofetch 
apt-get -y install lsof 
apt-get -y install openssl 
apt-get -y install openvpn 
apt-get -y install easy-rsa 
apt-get -y install fail2ban 
apt-get -y install tmux 
apt-get -y install stunnel4 
apt-get -y install squid3 
apt-get -y install socat 
apt-get -y install cron 
apt-get -y install bash-completion 
apt-get -y install ntpdate 
apt-get -y install apt-transport-https
apt-get -y install chrony 
apt-get -y install speedtest-cli
apt-get -y install p7zip-full 
apt-get -y install python3 
apt-get -y install python3-pip 
apt-get -y install shc 
apt-get -y install nodejs
apt-get -y install nginx 
apt-get -y install php 
apt-get -y install php-cli 
apt-get -y install dropbear

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
