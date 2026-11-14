#!/bin/sh
REPO="https://raw.githubusercontent.com/vudubai-2026/openwrt-m3-cockpit/main"
mkdir -p /etc/devmgr /www/cgi-bin /etc/crontabs

echo "== 1. Tai ban cap nhat v2.0 tu GitHub =="
for f in www/devmgr.html www/login.html www/cgi-bin/devmgr www/cgi-bin/devmgr-login www/cgi-bin/devmgr-net etc/devmgr/api.sh etc/devmgr/net_api.sh etc/devmgr/init.sh etc/devmgr/failover.sh; do
  wget -qO "/$f" "$REPO/$f" || { echo "Loi tai $f"; exit 1; }
done
chmod +x /etc/devmgr/*.sh /www/cgi-bin/devmgr*

echo "== 2. Kiem tra goi & Cron =="
for p in iw jsonfilter nft ubus curl; do command -v $p >/dev/null 2>&1 || echo "CANH BAO: thieu $p (apk add $p)"; done
grep -q 'devmgr/init.sh' /etc/rc.local || sed -i '/^exit 0/i /etc/devmgr/init.sh' /etc/rc.local
/etc/devmgr/init.sh

grep -q 'devmgr/failover.sh' /etc/crontabs/root 2>/dev/null || echo '*/2 * * * * /etc/devmgr/failover.sh' >> /etc/crontabs/root
/etc/init.d/cron enable >/dev/null 2>&1
/etc/init.d/cron restart
/etc/init.d/uhttpd restart
echo "XONG v2.0! Truy cap http://$(uci get network.lan.ipaddr)/devmgr.html"
