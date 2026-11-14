#!/bin/sh
printf 'Content-Type: application/json\r\nCache-Control: no-store\r\n\r\n'
ok(){ echo '{"ok":true}'; exit 0; }
err(){ printf '{"ok":false,"error":"%s"}\n' "$1"; exit 0; }

if [ "$REQUEST_METHOD" = "POST" ]; then
  body=$(head -c "${CONTENT_LENGTH:-0}")
  act=$(jsonfilter -s "$body" -e '@.action' 2>/dev/null)
else
  act=$(echo "$QUERY_STRING" | sed -n 's/.*action=\([a-z_]*\).*/\1/p')
fi

get_sta_iface() {
  uci show wireless 2>/dev/null | sed -n "s/^\(wireless\.[^.]*\)\.mode=.sta./\1/p" | head -1
}

get_wan_dev() {
  ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -1
}

case "$act" in
  status)
    SQM_EN=$(uci -q get sqm.@queue[0].enabled || echo 0)
    SQM_DL=$(uci -q get sqm.@queue[0].download || echo 0)
    SQM_UL=$(uci -q get sqm.@queue[0].upload || echo 0)
    IFACE=$(get_sta_iface)
    SSID=$(uci -q get "${IFACE}.ssid" || echo "Chưa kết nối")
    FO_EN=0; [ -f /etc/devmgr/repeater.conf ] && . /etc/devmgr/repeater.conf && FO_EN=${ENABLED:-0}
    SAVED=$(awk -F'|' 'NF>=2{gsub(/"/,"",$1); printf "\"%s\",",$1}' /etc/devmgr/wifi_backup.list 2>/dev/null | sed 's/,$//')
    FREE_MB=$(awk '/MemAvailable:/{printf "%.1f", $2/1024}' /proc/meminfo 2>/dev/null || echo "0")
    PING_MS=$(ping -c 1 -W 1 1.1.1.1 2>/dev/null | sed -n 's/.*time=\([0-9.]*\).*/\1/p' | head -1)
    printf '{"ok":true,"ver":"2.0","free_mb":"%s","ping":"%s","sqm_en":%s,"sqm_dl":%s,"sqm_ul":%s,"ssid":"%s","fo_en":%s,"saved":[%s]}\n' \
      "$FREE_MB" "${PING_MS:-timeout}" "$SQM_EN" "$SQM_DL" "$SQM_UL" "$SSID" "$FO_EN" "$SAVED"
    exit 0 ;;

  clean_ram)
    rm -f /tmp/*.tmp /tmp/dm_fail /tmp/luci-indexcache* 2>/dev/null
    sync && echo 3 > /proc/sys/vm/drop_caches 2>/dev/null
    FREE_MB=$(awk '/MemAvailable:/{printf "%.1f", $2/1024}' /proc/meminfo 2>/dev/null || echo "0")
    printf '{"ok":true,"free_mb":"%s"}\n' "$FREE_MB"
    exit 0 ;;

  sqm_toggle)
    [ -f /etc/config/sqm ] || err "Router chưa cài gói sqm-scripts"
    EN=$(jsonfilter -s "$body" -e '@.enabled')
    uci set sqm.@queue[0].enabled="$EN"
    uci commit sqm
    /etc/init.d/sqm reload >/dev/null 2>&1
    ok ;;

  sqm_auto)
    [ -f /etc/config/sqm ] || err "Router chưa cài gói sqm-scripts"
    command -v curl >/dev/null 2>&1 || err "Thiếu gói curl (chạy: apk add curl)"
    DL_BPS=$(curl -s -o /dev/null -w '%{speed_download}' --max-time 4 "https://speed.cloudflare.com/__down?bytes=8000000" 2>/dev/null | cut -d. -f1)
    UL_BPS=$(dd if=/dev/zero bs=1M count=3 2>/dev/null | curl -s -o /dev/null -w '%{speed_upload}' --max-time 4 -X POST --data-binary @- "https://speed.cloudflare.com/__up" 2>/dev/null | cut -d. -f1)
    [ -z "$DL_BPS" ] || [ "$DL_BPS" -lt 100000 ] && err "Không đo được mạng Internet"
    DL_K=$(( (DL_BPS * 8 * 85) / 100000 ))
    UL_K=$(( (${UL_BPS:-$((DL_BPS/2))} * 8 * 85) / 100000 ))
    [ "$UL_K" -lt 1000 ] && UL_K=$((DL_K / 2))
    WDEV=$(get_wan_dev)
    [ -n "$WDEV" ] && uci set sqm.@queue[0].interface="$WDEV"
    uci set sqm.@queue[0].download="$DL_K"
    uci set sqm.@queue[0].upload="$UL_K"
    uci set sqm.@queue[0].enabled="1"
    uci commit sqm
    /etc/init.d/sqm reload >/dev/null 2>&1
    sync && echo 3 > /proc/sys/vm/drop_caches 2>/dev/null
    printf '{"ok":true,"dl":%s,"ul":%s}\n' "$DL_K" "$UL_K"
    exit 0 ;;

  wifi_scan)
    IFACE=$(get_sta_iface)
    DEV=$(uci -q get "${IFACE}.device" || echo "radio0")
    LIST=$(iw dev "$DEV" scan 2>/dev/null | awk '/^BSS /{if(s)print sig"|"s; s=""; sig=-100} /signal:/{sig=int($2)} /SSID:/{sub(/^[ \t]*SSID: /,""); s=$0} END{if(s)print sig"|"s}' | sort -rn | head -12 | awk -F'|' '{gsub(/"/,"",$2); printf "{\"ssid\":\"%s\",\"sig\":%s},", $2, $1}' | sed 's/,$//')
    printf '{"ok":true,"aps":[%s]}\n' "$LIST"
    exit 0 ;;

  wifi_save)
    SSID=$(jsonfilter -s "$body" -e '@.ssid' | tr -d '\r\n|')
    PASS=$(jsonfilter -s "$body" -e '@.pass' | tr -d '\r\n|')
    SW=$(jsonfilter -s "$body" -e '@.switch_now')
    [ -z "$SSID" ] && err "Tên Wi-Fi trống"
    grep -vF "${SSID}|" /etc/devmgr/wifi_backup.list 2>/dev/null > /tmp/wb.tmp
    echo "${SSID}|${PASS}|psk2" >> /tmp/wb.tmp
    mv /tmp/wb.tmp /etc/devmgr/wifi_backup.list
    if [ "$SW" = "true" ]; then
      IFACE=$(get_sta_iface)
      [ -z "$IFACE" ] && err "Chưa bật chế độ Repeater (STA)"
      DEV=$(uci -q get "${IFACE}.device")
      uci set "${IFACE}.ssid=$SSID"
      uci set "${IFACE}.key=$PASS"
      uci set "${IFACE}.encryption=psk2"
      uci commit wireless
      (sleep 1; wifi reload "$DEV") >/dev/null 2>&1 &
    fi
    ok ;;

  wifi_del)
    SSID=$(jsonfilter -s "$body" -e '@.ssid' | tr -d '\r\n|')
    grep -vF "${SSID}|" /etc/devmgr/wifi_backup.list 2>/dev/null > /tmp/wb.tmp
    mv /tmp/wb.tmp /etc/devmgr/wifi_backup.list
    ok ;;

  failover_toggle)
    EN=$(jsonfilter -s "$body" -e '@.enabled')
    echo "ENABLED=$EN" > /etc/devmgr/repeater.conf
    ok ;;

  *) err "Action không hợp lệ: $act" ;;
esac
