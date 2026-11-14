#!/bin/sh
REPO="https://raw.githubusercontent.com/vudubai-2026/openwrt-m3-cockpit/main"
mkdir -p /etc/devmgr /www/cgi-bin

echo "== 1. Tai file tu GitHub =="
for f in www/devmgr.html www/login.html www/cgi-bin/devmgr www/cgi-bin/devmgr-login etc/devmgr/api.sh etc/devmgr/init.sh etc/devmgr/net_ext.sh etc/devmgr/failover.sh; do
  wget -qO "/$f" "$REPO/$f" || { echo "Loi tai $f"; exit 1; }
done
chmod +x /etc/devmgr/*.sh /www/cgi-bin/devmgr*

echo "== 2. Kiem tra goi & Cron Failover =="
for p in iw jsonfilter nft ubus curl; do command -v $p >/dev/null 2>&1 || echo "CANH BAO: thieu $p (apk add $p)"; done
command -v etherwake >/dev/null 2>&1 || { apk update >/dev/null 2>&1; apk add etherwake >/dev/null 2>&1; }

grep -q 'devmgr/init.sh' /etc/rc.local || sed -i '/^exit 0/i /etc/devmgr/init.sh' /etc/rc.local
/etc/devmgr/init.sh

touch /etc/crontabs/root
grep -q 'devmgr/failover.sh' /etc/crontabs/root || echo '*/2 * * * * /etc/devmgr/failover.sh' >> /etc/crontabs/root
/etc/init.d/cron restart

/etc/init.d/uhttpd restart
echo "XONG! Truy cap http://$(uci get network.lan.ipaddr)/devmgr.html"
