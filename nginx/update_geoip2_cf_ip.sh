# 存成：/root/setup_geoip_cf.sh 並執行：sudo bash /root/setup_geoip_cf.sh
#!/usr/bin/env bash
set -euo pipefail

# === 參數（可改） ===
GEOIP_DIR="/etc/nginx/geoip"
CF_V4_URL="https://www.cloudflare.com/ips-v4"
CF_V6_URL="https://www.cloudflare.com/ips-v6"
COUNTRY_URL="https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-Country.mmdb"
CITY_URL="https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-City.mmdb"
ASN_URL="https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-ASN.mmdb"
CF_LOCAL_TRUST=( "127.0.0.1" "192.168.25.112" )   # 同機 cloudflared/本機來源（需要時可增刪）
CRON_SPEC="0 3 * * 3,6"                           # 每周三、六 03:00

need() { command -v "$1" >/dev/null 2>&1 || { echo "缺少指令：$1"; exit 1; }; }
need curl
need awk
need sed
need nginx

echo "== 建立目錄：$GEOIP_DIR =="
install -d -m 0755 "$GEOIP_DIR"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

fetch_mmdb() {
  local url="$1" name="$2"
  echo " 下載 $name ..."
  if curl -fL --retry 3 -o "$TMP/$name" "$url"; then
    install -m 0644 "$TMP/$name" "$GEOIP_DIR/$name"
  else
    echo " !! 無法下載 $name（$url），保留現有檔案" >&2
  fi
}

echo "== 更新 GeoLite2 mmdb =="
fetch_mmdb "$COUNTRY_URL" "GeoLite2-Country.mmdb"
fetch_mmdb "$CITY_URL"    "GeoLite2-City.mmdb"
fetch_mmdb "$ASN_URL"     "GeoLite2-ASN.mmdb"

echo "== 產生 Cloudflare real_ip 清單（v4/v6） =="
# 先寫到暫存，再原子替換
curl -fsS "$CF_V4_URL" | awk '{print "set_real_ip_from " $1 ";"}' > "$TMP/cloudflare_v4_realip.conf"
curl -fsS "$CF_V6_URL" | awk '{print "set_real_ip_from " $1 ";"}' > "$TMP/cloudflare_v6_realip.conf"
install -m 0644 "$TMP/cloudflare_v4_realip.conf" "$GEOIP_DIR/cloudflare_v4_realip.conf"
install -m 0644 "$TMP/cloudflare_v6_realip.conf" "$GEOIP_DIR/cloudflare_v6_realip.conf"

echo "== 寫入本機/內網信任來源（cloudflared/本機） =="
{
  for ip in "${CF_LOCAL_TRUST[@]}"; do
    [[ -n "$ip" ]] && echo "set_real_ip_from $ip;"
  done
} > "$TMP/cloudflared_realip.conf"
install -m 0644 "$TMP/cloudflared_realip.conf" "$GEOIP_DIR/cloudflared_realip.conf"

# 建立更新腳本
echo "== 安裝 /usr/local/sbin/update_geoip2.sh =="
cat >/usr/local/sbin/update_geoip2.sh <<'UPD'
#!/usr/bin/env bash
set -euo pipefail
GEOIP_DIR="/etc/nginx/geoip"
CF_V4_URL="https://www.cloudflare.com/ips-v4"
CF_V6_URL="https://www.cloudflare.com/ips-v6"
COUNTRY_URL="https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-Country.mmdb"
CITY_URL="https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-City.mmdb"
ASN_URL="https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-ASN.mmdb"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

dl() { curl -fL --retry 3 -o "$2" "$1" && install -m 0644 "$2" "$3"; }

# mmdb 更新（失敗不影響現有檔）
dl "$COUNTRY_URL" "$TMP/GeoLite2-Country.mmdb" "$GEOIP_DIR/GeoLite2-Country.mmdb" || true
dl "$CITY_URL"    "$TMP/GeoLite2-City.mmdb"    "$GEOIP_DIR/GeoLite2-City.mmdb"    || true
dl "$ASN_URL"     "$TMP/GeoLite2-ASN.mmdb"     "$GEOIP_DIR/GeoLite2-ASN.mmdb"     || true

# CF v4/v6 清單
curl -fsS "$CF_V4_URL" | awk '{print "set_real_ip_from " $1 ";"}' > "$TMP/cloudflare_v4_realip.conf"
curl -fsS "$CF_V6_URL" | awk '{print "set_real_ip_from " $1 ";"}' > "$TMP/cloudflare_v6_realip.conf"
install -m 0644 "$TMP/cloudflare_v4_realip.conf" "$GEOIP_DIR/cloudflare_v4_realip.conf"
install -m 0644 "$TMP/cloudflare_v6_realip.conf" "$GEOIP_DIR/cloudflare_v6_realip.conf"

# 測試並熱重載 NGINX
if nginx -t; then
  nginx -s reload
  echo "[OK] GeoIP/CF 清單已更新並重新載入 NGINX"
else
  echo "[WARN] nginx -t 失敗，未重載（請修正設定）" >&2
fi
UPD
chmod +x /usr/local/sbin/update_geoip2.sh

echo "== 先執行一次更新腳本 =="
/usr/local/sbin/update_geoip2.sh || true

echo "== 設定 crontab（$CRON_SPEC 每週兩次） =="
# 先移除舊的 update_geoip2.sh 排程
sed -i '\#update_geoip2.sh#d' /etc/crontab
# 新增：每周三、六 03:00 執行
echo "$CRON_SPEC root /usr/local/sbin/update_geoip2.sh >/var/log/update_geoip2.log 2>&1" >> /etc/crontab
systemctl reload cron 2>/dev/null || service cron reload 2>/dev/null || true

echo "== 最後檢查 NGINX 設定 =="
nginx -t && echo "完成 ✅ 可在 /var/log/update_geoip2.log 查看之後的排程輸出。"
