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
apt-get --assume-yes install iptables
apt-get --assume-yes install iptables-persistent 
apt-get --assume-yes install netfilter-persistent
apt-get --assume-yes install figlet
apt-get --assume-yes install ruby 
apt-get --assume-yes install libxml-parser-perl 
apt-get --assume-yes install squid 
apt-get --assume-yes install nmap 
apt-get --assume-yes install rsyslog 
apt-get --assume-yes install iftop 
apt-get --assume-yes install htop 
apt-get --assume-yes install zip 
apt-get --assume-yes install unzip 
apt-get --assume-yes install net-tools 
apt-get --assume-yes install sed 
apt-get --assume-yes install bc 
apt-get --assume-yes install apt-transport-https
apt-get ---assume-yes install build-essential 
apt-get --assume-yes install libxml-parser-perl 
apt-get --assume-yes install neofetch 
apt-get --assume-yes install lsof 
apt-get --assume-yes install openssl 
apt-get --assume-yes install openvpn 
apt-get --assume-yes install easy-rsa 
apt-get --assume-yes install fail2ban 
apt-get --assume-yes install tmux 
apt-get --assume-yes install stunnel4 
apt-get --assume-yes install squid3 
apt-get --assume-yes install socat 
apt-get --assume-yes install cron 
apt-get --assume-yes install bash-completion 
apt-get --assume-yes install ntpdate 
apt-get --assume-yes install apt-transport-https
apt-get --assume-yes install chrony 
apt-get --assume-yes install speedtest-cli
apt-get --assume-yes install p7zip-full 
apt-get --assume-yes install python3 
apt-get --assume-yes install python3-pip 
apt-get --assume-yes install shc 
apt-get --assume-yes install nodejs
apt-get --assume-yes install nginx 
apt-get --assume-yes install php 
apt-get --assume-yes install php-fpm
apt-get --assume-yes install php-cli 
apt-get --assume-yes install dropbear

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

# // install lolcat
wget https://raw.githubusercontent.com/casper9/script/main/lolcat.sh &&  chmod +x lolcat.sh && ./lolcat.sh

yellow() { echo -e "\\033[33;1m${*}\\033[0m"; }
yellow "Dependencies successfully installed..."
sleep 1
clear

mkdir -p /etc/tools
