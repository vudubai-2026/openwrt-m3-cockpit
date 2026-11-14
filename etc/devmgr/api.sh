#!/bin/sh
D=${D:-/tmp/devmgr}; P=${P:-/etc/devmgr}
mkdir -p "$D" "$P"
for f in names.tsv blocked.list blacklist.list qos.tsv; do [ -f "$P/$f" ] || : > "$P/$f"; done
ok(){ echo '{"ok":true}'; exit 0; }
err(){ printf '{"ok":false,"error":"%s"}\n' "$1"; exit 0; }

list() {
  now=$(date +%s)
  : > "$D/st.tsv"
  for i in $(iw dev | awk '$1=="Interface"{print $2}'); do
    fq=$(iw dev "$i" info | awk '$1=="channel"{gsub(/[(]/,"");print $3}')
    [ -n "$fq" ] || continue
    iw dev "$i" info | grep -q "type AP" || continue
    b=5G; [ "$fq" -lt 3000 ] && b=2.4G
    iw dev "$i" station dump | awk -v i="$i" -v b="$b" '
      $1=="Station"{if(m)print m"\t"i"\t"b"\t"s"\t"r"\t"t; m=toupper($2);s=0;r=0;t=0}
      $1=="signal:"{s=$2}
      $1=="rx"&&$2=="bytes:"{r=$3}
      $1=="tx"&&$2=="bytes:"{t=$3}
      END{if(m)print m"\t"i"\t"b"\t"s"\t"r"\t"t}' >> "$D/st.tsv"
  done
  awk '{h=$4; if(h=="*")h=""; print toupper($2)"\t"$3"\t"h}' /tmp/dhcp.leases > "$D/ls.tsv" 2>/dev/null
  ip neigh show dev br-lan 2>/dev/null | awk '$3=="lladdr" && $1!~/:/{print toupper($4)"\t"$1"\t"$NF}' > "$D/nb.tsv"
  [ -f "$D/prev.tsv" ] || : > "$D/prev.tsv"
  awk -F'\t' -v now="$now" -v pn="$D/prev.new" '
  function esc(s){gsub(/\\/,"\\\\",s);gsub(/"/,"\\\"",s);gsub(/[\001-\037]/,"",s);return s}
  function seen(m){if(!(m in all)){all[m]=1;ord[++n]=m}}
  FILENAME~/names\.tsv$/{nm[$1]=$2;seen($1);next}
  FILENAME~/qos\.tsv$/{qr[$1]=$2;seen($1);next}
  FILENAME~/blocked\.list$/{if($1!=""){bk[toupper($1)]=1;seen(toupper($1))};next}
  FILENAME~/blacklist\.list$/{if($1!=""){bl[toupper($1)]=1;seen(toupper($1))};next}
  FILENAME~/prev\.tsv$/{prx[$1]=$2;ptx[$1]=$3;pts[$1]=$4;next}
  FILENAME~/ls\.tsv$/{lip[$1]=$2;lhn[$1]=$3;seen($1);next}
  FILENAME~/nb\.tsv$/{nip[$1]=$2;nst[$1]=$3;seen($1);next}
  FILENAME~/st\.tsv$/{sf[$1]=$2;sb[$1]=$3;ss[$1]=$4;sr[$1]=$5;st[$1]=$6;seen($1);next}
  END{
    printf "{\"devices\":[";
    for(k=1;k<=n;k++){
      m=ord[k]; ip=(m in lip)?lip[m]:nip[m]; wifi=(m in sf)
      on=wifi||(nst[m]=="REACHABLE"||nst[m]=="DELAY")
      dn=0;up=0
      if(wifi){
        print m"\t"sr[m]"\t"st[m]"\t"now > pn
        if((m in pts)&&now>pts[m]){dt=now-pts[m];dn=(st[m]-ptx[m])/dt;up=(sr[m]-prx[m])/dt;if(dn<0)dn=0;if(up<0)up=0}
      }
      printf "%s{\"mac\":\"%s\",\"ip\":\"%s\",\"hostname\":\"%s\",\"name\":\"%s\",\"vendor\":\"\",\"iface\":\"%s\",\"band\":\"%s\",\"signal\":%d,\"rx\":%d,\"tx\":%d,\"qos_rate\":%d,\"online\":%s,\"blocked\":%s,\"blacklisted\":%s}",
        (k>1?",":""),m,ip,esc(lhn[m]),esc(nm[m]),wifi?sf[m]:"br-lan",wifi?sb[m]:"LAN",wifi?ss[m]:0,dn,up,qr[m]+0,on?"true":"false",(m in bk)?"true":"false",(m in bl)?"true":"false"
    }
    printf "]}\n"
  }' "$P/names.tsv" "$P/qos.tsv" "$P/blocked.list" "$P/blacklist.list" "$D/prev.tsv" "$D/ls.tsv" "$D/nb.tsv" "$D/st.tsv"
  [ -f "$D/prev.new" ] && mv "$D/prev.new" "$D/prev.tsv" || : > "$D/prev.tsv"
}

setadd(){ grep -qix "$3" "$P/$2" || echo "$3" >> "$P/$2"; nft add element inet devmgr "$1" "{ $3 }" 2>/dev/null; }
setdel(){ if grep -qix "$3" "$P/$2"; then grep -vix "$3" "$P/$2" > "$D/t"; cat "$D/t" > "$P/$2"; fi; nft delete element inet devmgr "$1" "{ $3 }" 2>/dev/null; }
kick(){ a=$(echo "$1" | tr 'A-F' 'a-f'); for h in $(ubus list 'hostapd.*'); do ubus call "$h" del_client "{\"addr\":\"$a\",\"reason\":5,\"deauth\":true,\"ban_time\":10000}" >/dev/null 2>&1; done; }
qos_clear(){ for h in $(nft -a list chain inet devmgr dm_fwd 2>/dev/null | awk -v c="dmq_$1" 'index($0,"\""c"\""){print $NF}'); do nft delete rule inet devmgr dm_fwd handle "$h" 2>/dev/null; done; }
qos_apply(){
  nft add rule inet devmgr dm_fwd ether saddr "$1" limit rate over "$2" kbytes/second burst "$2" kbytes drop comment "\"dmq_$1\"" 2>/dev/null
  ip=$(awk -v m="$1" 'toupper($2)==m{print $3}' /tmp/dhcp.leases 2>/dev/null | head -1)
  [ -n "$ip" ] && nft add rule inet devmgr dm_fwd ip daddr "$ip" limit rate over "$2" kbytes/second burst "$2" kbytes drop comment "\"dmq_$1\"" 2>/dev/null
}

if [ "$1" = reapply ]; then
  while IFS="$(printf '\t')" read -r m r; do [ -n "$m" ] && qos_apply "$m" "$r"; done < "$P/qos.tsv"
  exit 0
fi
printf 'Content-Type: application/json\r\nCache-Control: no-store\r\n\r\n'

if [ "$REQUEST_METHOD" != "POST" ]; then
  case "$QUERY_STRING" in *action=list*) list; exit 0;; esac
  err "bad request"
fi

[ "${CONTENT_LENGTH:-0}" -gt 600 ] && err "payload qua lon"
body=$(head -c "${CONTENT_LENGTH:-0}")
act=$(jsonfilter -s "$body" -e '@.action')
mac=$(jsonfilter -s "$body" -e '@.mac' | tr 'a-f' 'A-F')
case "$act" in net_status|sqm_toggle|sqm_auto|wifi_scan|wifi_save|failover_toggle) . /etc/devmgr/net_ext.sh ;; esac
echo "$mac" | grep -Eq '^([0-9A-F]{2}:){5}[0-9A-F]{2}$' || err "MAC khong hop le"
nft list table inet devmgr >/dev/null 2>&1 || /etc/devmgr/init.sh

case "$act" in
  block)            setadd blocked blocked.list "$mac"; ok;;
  unblock)          setdel blocked blocked.list "$mac"; ok;;
  blacklist_add)    setadd blacklist blacklist.list "$mac"; kick "$mac"; ok;;
  blacklist_remove) setdel blacklist blacklist.list "$mac"; ok;;
  kick)             kick "$mac"; ok;;
  wol)
    for c in etherwake ether-wake; do
      command -v $c >/dev/null 2>&1 && { $c -i br-lan "$mac" >/dev/null 2>&1; ok; }
    done
    err "chua cai etherwake: apk add etherwake";;
  rename)
    name=$(jsonfilter -s "$body" -e '@.name' | tr -d '\t\r\n\\"')
    [ "$(printf %s "$name" | wc -c)" -gt 80 ] && err "ten qua dai"
    cur=$(awk -F'\t' -v m="$mac" '$1==m{print $2}' "$P/names.tsv")
    [ "$cur" = "$name" ] && ok
    awk -F'\t' -v m="$mac" '$1!=m' "$P/names.tsv" > "$D/t"
    [ -n "$name" ] && printf '%s\t%s\n' "$mac" "$name" >> "$D/t"
    cat "$D/t" > "$P/names.tsv"; ok;;
  qos_limit)
    rate=$(jsonfilter -s "$body" -e '@.rate')
    case "$rate" in ''|*[!0-9]*) err "toc do khong hop le";; esac
    [ "$rate" -gt 1000000 ] && err "toc do qua lon"
    [ "$rate" -ne 0 ] && [ "$rate" -lt 16 ] && err "toi thieu 16 KB/s"
    cur=$(awk -F'\t' -v m="$mac" '$1==m{print $2}' "$P/qos.tsv")
    [ "${cur:-0}" = "$rate" ] && ok
    qos_clear "$mac"
    awk -F'\t' -v m="$mac" '$1!=m' "$P/qos.tsv" > "$D/t"
    if [ "$rate" -gt 0 ]; then printf '%s\t%s\n' "$mac" "$rate" >> "$D/t"; qos_apply "$mac" "$rate"; fi
    cat "$D/t" > "$P/qos.tsv"; ok;;
  static_lease)
    ip=$(jsonfilter -s "$body" -e '@.ip')
    echo "$ip" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$' || err "IP khong hop le"
    lan=$(ip -4 -o addr show br-lan | awk '{split($4,a,"/");print a[1]}' | head -1)
    [ "${ip%.*}" = "${lan%.*}" ] || err "IP phai cung lop mang voi router"
    [ "${ip##*.}" -ge 2 ] && [ "${ip##*.}" -le 254 ] || err "IP khong hop le"
    s="dm_$(echo "$mac" | tr -d ':' | tr 'A-F' 'a-f')"
    [ "$(uci -q get dhcp.$s.ip)" = "$ip" ] && ok
    uci -q show dhcp | grep "^dhcp\.[^.]*\.ip='$ip'$" | grep -vq "^dhcp\.$s\." && err "IP da duoc gan cho may khac"
    uci set dhcp.$s=host; uci set dhcp.$s.mac="$mac"; uci set dhcp.$s.ip="$ip"
    uci commit dhcp; /etc/init.d/dnsmasq reload >/dev/null 2>&1; ok;;
  *) err "action khong hop le";;
esac
