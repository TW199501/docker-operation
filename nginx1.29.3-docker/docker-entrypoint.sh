#!/bin/sh
set -e

# Seed default config if /etc/nginx is empty or missing nginx.conf
if [ ! -f /etc/nginx/nginx.conf ]; then
  echo "[entrypoint] Seeding default nginx config..."
  cp -a /opt/seed/etc-nginx/. /etc/nginx/
fi

# Seed modules if /usr/lib/nginx/modules is empty
if [ ! -d /usr/lib/nginx/modules ] || [ -z "$(ls -A /usr/lib/nginx/modules 2>/dev/null)" ]; then
  echo "[entrypoint] Seeding nginx modules..."
  mkdir -p /usr/lib/nginx/modules
  cp -a /opt/seed/modules/. /usr/lib/nginx/modules/
fi

# Seed GeoIP data if /usr/share/GeoIP is empty
if [ ! -d /usr/share/GeoIP ] || [ -z "$(ls -A /usr/share/GeoIP 2>/dev/null)" ]; then
  if [ -d /opt/seed/geoip ] && [ -n "$(ls -A /opt/seed/geoip 2>/dev/null)" ]; then
    echo "[entrypoint] Seeding GeoIP data..."
    mkdir -p /usr/share/GeoIP
    cp -a /opt/seed/geoip/. /usr/share/GeoIP/
  fi
fi

# Test nginx configuration
echo "[entrypoint] Testing nginx configuration..."
nginx -t

# Execute the main command
exec "$@"
