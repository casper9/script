#!/bin/bash

apt install rclone
printf "q\n" | rclone config
wget -O /root/.config/rclone/rclone.conf "https://raw.githubusercontent.com/casper9/script/main/rclone.conf"
git clone  https://github.com/casper9/wondershaper.git
cd wondershaper
make install
cd
rm -rf wondershaper
wget -O /usr/bin/cleaner "https://raw.githubusercontent.com/casper9/script/main/cleaner.sh"
wget -O /usr/bin/xp "https://raw.githubusercontent.com/casper9/script/main/xp.sh"
wget -O /usr/bin/bantwidth "https://raw.githubusercontent.com/casper9/script/main/bantwidth"
chmod +x /usr/bin/bantwidth
chmod +x /usr/bin/cleaner
chmod +x /usr/bin/xp
cd
if [ ! -f "/etc/cron.d/cleaner" ]; then
cat> /etc/cron.d/cleaner << END
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
*/2 * * * * root /usr/bin/cleaner
END
fi

if [ ! -f "/etc/cron.d/xp_otm" ]; then
cat> /etc/cron.d/xp_otm << END
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
0 0 * * * root /usr/bin/xp
END
fi
cat > /home/re_otm <<-END
7
END

if [ ! -f "/etc/cron.d/bckp_otm" ]; then
cat> /etc/cron.d/bckp_otm << END
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
0 5 * * * root /usr/bin/bottelegram
END
fi

if [ ! -f "etc/systemd/system/autocpu.service" ]; then
cat> /etc/systemd/system/autocpu.service << END
[Unit]
Description=Autocpu
After=network.target

[Service]
ExecStart=/usr/bin/autocpu
Restart=always
RestartSec=10

[Install]
WantedBy=default.target
END

fi

service cron restart > /dev/null 2>&1
systemctl enable autocpu
systemctl restart autocpu
    
rm -f /root/set-br.sh
