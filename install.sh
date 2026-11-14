#!/bin/sh
REPO="https://raw.githubusercontent.com/vudubai-2026/openwrt-m3-cockpit/main"
mkdir -p /etc/devmgr /www/cgi-bin
echo "== 1. Tai file tu GitHub =="
wget -qO /www/devmgr.html "$REPO/www/devmgr.html" || { echo "Loi tai devmgr.html"; exit 1; }
wget -qO /www/login.html "$REPO/www/login.html"
wget -qO /etc/devmgr/api.sh "$REPO/etc/devmgr/api.sh"
wget -qO /etc/devmgr/init.sh "$REPO/etc/devmgr/init.sh"
wget -qO /www/cgi-bin/devmgr "$REPO/www/cgi-bin/devmgr"
wget -qO /www/cgi-bin/devmgr-login "$REPO/www/cgi-bin/devmgr-login"
chmod +x /etc/devmgr/*.sh /www/cgi-bin/devmgr*
echo "== 2. Kiem tra goi & khoi dong =="
for p in iw jsonfilter nft ubus; do command -v $p >/dev/null 2>&1 || echo "Thieu $p"; done
command -v etherwake >/dev/null 2>&1 || { apk update >/dev/null 2>&1; apk add etherwake >/dev/null 2>&1; }
grep -q "devmgr/init.sh" /etc/rc.local || sed -i "/^exit 0/i /etc/devmgr/init.sh" /etc/rc.local
/etc/devmgr/init.sh
/etc/init.d/uhttpd restart
echo "XONG! Truy cap http://$(uci get network.lan.ipaddr)/devmgr.html"
