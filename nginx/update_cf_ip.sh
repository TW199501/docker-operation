# /usr/local/sbin/update-cf-ipsets.sh
#!/usr/bin/env bash
set -euo pipefail
v4=$(mktemp) ; v6=$(mktemp)
curl -fsS https://www.cloudflare.com/ips-v4 > "$v4"
curl -fsS https://www.cloudflare.com/ips-v6 > "$v6"

# 先移除舊條目
for e in $(firewall-cmd --permanent --ipset=cloudflare4 --get-entries 2>/dev/null); do
  firewall-cmd --permanent --ipset=cloudflare4 --remove-entry="$e" || true
done
for e in $(firewall-cmd --permanent --ipset=cloudflare6 --get-entries 2>/dev/null); do
  firewall-cmd --permanent --ipset=cloudflare6 --remove-entry="$e" || true
done

# 加入新清單
xargs -r -I{} firewall-cmd --permanent --ipset=cloudflare4 --add-entry={} < "$v4"
xargs -r -I{} firewall-cmd --permanent --ipset=cloudflare6 --add-entry={} < "$v6"

firewall-cmd --reload
rm -f "$v4" "$v6"
echo "[OK] Cloudflare ipsets updated."
