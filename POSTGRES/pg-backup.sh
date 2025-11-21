#!/bin/sh
set -e

# PG 連線設定（由 docker-compose 傳進來）
: "${PGHOST:?PGHOST is required}"
: "${PGPORT:?PGPORT is required}"
: "${PGUSER:?PGUSER is required}"
: "${PGPASSWORD:?PGPASSWORD is required}"

# MinIO / S3 設定
: "${MINIO_ALIAS:?MINIO_ALIAS is required}"
: "${MINIO_URL:?MINIO_URL is required}"
: "${MINIO_ACCESS_KEY:?MINIO_ACCESS_KEY is required}"
: "${MINIO_SECRET_KEY:?MINIO_SECRET_KEY is required}"
: "${MINIO_BUCKET:?MINIO_BUCKET is required}"

BACKUP_DIR="/backup"
DATE=$(date +%Y%m%d-%H%M%S)
FILE="${BACKUP_DIR}/pg-all-${DATE}.sql.gz"

echo "[$(date)] start pg_dumpall: ${FILE}"

mkdir -p "${BACKUP_DIR}"

# 1. 備份整個 PG cluster（所有 DB + 角色等）
pg_dumpall \
  -h "${PGHOST}" \
  -p "${PGPORT}" \
  -U "${PGUSER}" \
  | gzip > "${FILE}"

echo "[$(date)] pg_dumpall done, file: ${FILE}"

# 2. 設定 MinIO alias
mc alias set "${MINIO_ALIAS}" "${MINIO_URL}" "${MINIO_ACCESS_KEY}" "${MINIO_SECRET_KEY}"

# 3. 確保 bucket 存在
mc mb --ignore-existing "${MINIO_ALIAS}/${MINIO_BUCKET}"

# 4. 上傳備份檔到 MinIO
mc cp "${FILE}" "${MINIO_ALIAS}/${MINIO_BUCKET}/"

echo "[$(date)] upload to MinIO done"

# 5. 本機只保留 7 天（可依需要調整）
find "${BACKUP_DIR}" -type f -mtime +7 -name "*.sql.gz" -delete

echo "[$(date)] backup job finished"
