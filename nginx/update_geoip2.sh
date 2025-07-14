#!/bin/bash
#啟動安裝Geoip庫自動更新GeoIP2腳本


GEOIP_DIR="/etc/nginx/geoip"
TMP_DIR="/tmp/geoip2_update"
COUNTRY_URL="https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-Country.mmdb"
CITY_URL="https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-City.mmdb"

mkdir -p "$TMP_DIR"
wget -q -O "$TMP_DIR/GeoLite2-Country.mmdb" "$COUNTRY_URL"
[ -s "$TMP_DIR/GeoLite2-Country.mmdb" ] && mv "$TMP_DIR/GeoLite2-Country.mmdb" "$GEOIP_DIR/"
wget -q -O "$TMP_DIR/GeoLite2-City.mmdb" "$CITY_URL"
[ -s "$TMP_DIR/GeoLite2-City.mmdb" ] && mv "$TMP_DIR/GeoLite2-City.mmdb" "$GEOIP_DIR/"

sudo tee /etc/nginx/geoip/update_geoip2.sh >/dev/null <<'EOF'