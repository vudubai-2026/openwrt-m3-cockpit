#!/bin/sh
P=/etc/devmgr
nft delete table inet devmgr 2>/dev/null
nft add table inet devmgr
nft add set inet devmgr blocked '{ type ether_addr; }'
nft add set inet devmgr blacklist '{ type ether_addr; }'
nft add chain inet devmgr dm_fwd '{ type filter hook forward priority -5; policy accept; }'
nft add chain inet devmgr dm_in '{ type filter hook input priority -5; policy accept; }'
nft add rule inet devmgr dm_fwd ether saddr @blocked drop
nft add rule inet devmgr dm_fwd ether saddr @blacklist drop
nft add rule inet devmgr dm_in ether saddr @blacklist drop
for s in blocked blacklist; do
  [ -f $P/$s.list ] && for m in $(cat $P/$s.list); do nft add element inet devmgr $s "{ $m }"; done
done
/etc/devmgr/api.sh reapply 2>/dev/null
exit 0
