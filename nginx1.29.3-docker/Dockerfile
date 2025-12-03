# syntax=docker/dockerfile:1
FROM debian:trixie-slim

ENV DEBIAN_FRONTEND=noninteractive \
  NGINX_VERSION=1.29.3 \
  BUILD_DIR=/opt/nginx-build/work \
  AUTO_CONFIRM=1 \
  SKIP_SYSTEMD=1 \
  SKIP_NGINX_BOOT=1 \
  NGINX_ETC=/etc/nginx

RUN set -eux; \
  apt-get update; \
  apt-get install -y --no-install-recommends \
  build-essential \
  git curl wget ca-certificates gnupg pkg-config \
  procps iproute2 \
  libnl-3-dev libnl-genl-3-dev libnfnetlink-dev libnftnl-dev \
  libpopt-dev libsystemd-dev \
  libpcre2-dev zlib1g-dev libssl-dev \
  libmaxminddb0 libmaxminddb-dev mmdb-bin \
  autoconf gettext libncursesw5-dev unzip cmake \
  libbrotli-dev libxml2-dev libxslt1-dev libgd-dev \
  libmodsecurity3 libmodsecurity-dev \
  cron logrotate \
  tzdata; \
  rm -rf /var/lib/apt/lists/*

WORKDIR /opt/nginx-build
COPY nginx1.29.3-docker/build-nginx.sh ./build-nginx.sh
RUN chmod +x ./build-nginx.sh

RUN set -eux; \
  ./build-nginx.sh; \
  rm -rf "$BUILD_DIR"

COPY nginx1.29.3-docker/nginx.conf /etc/nginx/nginx.conf
COPY nginx1.29.3-docker/conf.d/cloudflare.conf /etc/nginx/conf.d/cloudflare.conf
COPY nginx1.29.3-docker/ssl/ssl.conf /etc/nginx/conf.d/ssl.conf
COPY nginx1.29.3-docker/geoip/ip_whitelist.conf /etc/nginx/geoip/ip_whitelist.conf
COPY nginx1.29.3-docker/geoip/ip_blacklist.conf /etc/nginx/geoip/ip_blacklist.conf
COPY nginx1.29.3-docker/scripts/manage_ip.sh /etc/nginx/scripts/manage_ip.sh
COPY nginx1.29.3-docker/ssl/ssl.conf /etc/nginx/ssl/ssl.conf
RUN chmod +x /etc/nginx/scripts/manage_ip.sh

COPY nginx1.29.3-docker/keepalived-install.sh /opt/keepalived-install.sh
RUN chmod +x /opt/keepalived-install.sh

COPY nginx1.29.3-docker/log/logrotate-nginx.conf /etc/logrotate.d/nginx

RUN set -eux; \
  mkdir -p /opt/seed/etc-nginx /opt/seed/modules /opt/seed/geoip /opt/seed/keepalived; \
  cp -a /etc/nginx/. /opt/seed/etc-nginx/; \
  cp -a /usr/lib/nginx/modules/. /opt/seed/modules/; \
  if [ -d /usr/share/GeoIP ]; then cp -a /usr/share/GeoIP/. /opt/seed/geoip/; fi; \
  if [ -d /etc/keepalived ]; then cp -a /etc/keepalived/. /opt/seed/keepalived/; fi

COPY nginx1.29.3-docker/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 80 443
STOPSIGNAL SIGQUIT
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
