#!/usr/bin/env bash
set -euo pipefail

# 更新 Cloudflare IPv4 真實 IP
/bin/curl -s https://www.cloudflare.com/ips-v4 \
  | /bin/awk '{print "set_real_ip_from " $1 ";"}' \
  > /etc/nginx/geoip/cloudflare_v4_realip.conf

# 更新 Cloudflare IPv6 真實 IP
/bin/curl -s https://www.cloudflare.com/ips-v6 \
  | /bin/awk '{print "set_real_ip_from " $1 ";"}' \
  > /etc/nginx/geoip/cloudflare_v6_realip.conf

