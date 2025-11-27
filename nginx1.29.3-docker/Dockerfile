# syntax=docker/dockerfile:1
FROM debian:bookworm-slim

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
      tzdata; \
    rm -rf /var/lib/apt/lists/*

WORKDIR /opt/nginx-build
COPY nginx1.29.3-docker/build-nginx.sh ./build-nginx.sh
COPY nginx1.29.3-docker/30-keepalived-install.sh ./30-keepalived-install.sh
RUN chmod +x ./build-nginx.sh ./30-keepalived-install.sh

RUN set -eux; \
    ./build-nginx.sh; \
    rm -rf "$BUILD_DIR"

RUN set -eux; \
    KEEPI_VER=2.3.4; \
    SRC_DIR=/usr/local/src; \
    mkdir -p "$SRC_DIR"; \
    cd "$SRC_DIR"; \
    curl -fSLo "keepalived-${KEEPI_VER}.tar.gz" "https://keepalived.org/software/keepalived-${KEEPI_VER}.tar.gz"; \
    tar -xzf "keepalived-${KEEPI_VER}.tar.gz"; \
    cd "keepalived-${KEEPI_VER}"; \
    ./configure --prefix=/usr --sysconfdir=/etc --with-systemd; \
    make -j"$(nproc)"; \
    make install; \
    rm -rf "$SRC_DIR/keepalived-${KEEPI_VER}" "$SRC_DIR/keepalived-${KEEPI_VER}.tar.gz"

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
