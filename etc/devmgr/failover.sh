#!/bin/sh
CFG="/etc/devmgr/repeater.conf"
LIST="/etc/devmgr/wifi_backup.list"
FAIL_F="/tmp/dm_fail"

[ ! -f "$CFG" ] && exit 0
. "$CFG"
[ "$ENABLED" != "1" ] && exit 0

if ping -c 2 -W 2 1.1.1.1 >/dev/null 2>&1 || ping -c 2 -W 2 8.8.8.8 >/dev/null 2>&1; then
  rm -f "$FAIL_F"
  exit 0
fi

cnt=$(cat "$FAIL_F" 2>/dev/null || echo 0)
cnt=$((cnt + 1))
echo "$cnt" > "$FAIL_F"
[ "$cnt" -lt 2 ] && exit 0

rm -f "$FAIL_F"
[ ! -s "$LIST" ] && exit 0

IFACE=$(uci show wireless | sed -n "s/^\(wireless\.[^.]*\)\.mode=.sta./\1/p" | head -1)
DEV=$(uci get "${IFACE}.device" 2>/dev/null)
[ -z "$IFACE" ] || [ -z "$DEV" ] && exit 0

CUR_SSID=$(uci get "${IFACE}.ssid" 2>/dev/null)
SCAN=$(iw dev "$DEV" scan 2>/dev/null | awk '/^BSS /{if(s)print sig"|"s; s=""; sig=-100} /signal:/{sig=int($2)} /SSID:/{sub(/^[ \t]*SSID: /,""); s=$0} END{if(s)print sig"|"s}' | sort -rn)

while IFS="|" read -r sig ssid; do
  [ -z "$ssid" ] || [ "$ssid" = "$CUR_SSID" ] && continue
  LINE=$(grep -F "${ssid}|" "$LIST" | head -1)
  if [ -n "$LINE" ]; then
    PASS=$(echo "$LINE" | cut -d"|" -f2)
    ENC=$(echo "$LINE" | cut -d"|" -f3)
    uci set "${IFACE}.ssid=$ssid"
    uci set "${IFACE}.key=$PASS"
    uci set "${IFACE}.encryption=${ENC:-psk2}"
    uci commit wireless
    wifi reload "$DEV"
    exit 0
  fi
done <<SCAN_EOF
$SCAN
SCAN_EOF
