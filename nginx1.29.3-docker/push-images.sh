#!/usr/bin/env bash
set -euo pipefail

NGINX_IMAGE_BASE="tw199501/nginx"
NGINX_VERSION="1.29.3"

HAPROXY_IMAGE_BASE="tw199501/haproxy"
HAPROXY_VERSION="trixie"

echo "[INFO] Tagging nginx image..."
docker tag "${NGINX_IMAGE_BASE}:${NGINX_VERSION}" "${NGINX_IMAGE_BASE}:latest"

echo "[INFO] Tagging haproxy image..."
docker tag "${HAPROXY_IMAGE_BASE}:${HAPROXY_VERSION}" "${HAPROXY_IMAGE_BASE}:latest"

echo "[INFO] Pushing nginx tags: ${NGINX_VERSION}, latest"
docker push "${NGINX_IMAGE_BASE}:${NGINX_VERSION}"
docker push "${NGINX_IMAGE_BASE}:latest"

echo "[INFO] Pushing haproxy tags: ${HAPROXY_VERSION}, latest"
docker push "${HAPROXY_IMAGE_BASE}:${HAPROXY_VERSION}"
docker push "${HAPROXY_IMAGE_BASE}:latest"

echo "[INFO] Done."
