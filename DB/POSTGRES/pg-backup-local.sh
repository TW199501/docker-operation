#!/bin/sh
set -e

# PG 連線設定，由 docker-compose 傳入
: "${PGHOST:?PGHOST is required}"
: "${PGPORT:?PGPORT is required}"
: "${PGUSER:?PGUSER is required}"
: "${PGPASSWORD:?PGPASSWORD is required}"

BACKUP_DIR="/backup"
DATE=$(date +%Y%m%d-%H%M%S)
FILE="${BACKUP_DIR}/pg-all-${DATE}.sql.gz"

echo "[$(date)] start pg_dumpall: ${FILE}"

mkdir -p "${BACKUP_DIR}"

# 備份整個 cluster（所有 DB + 角色）
pg_dumpall \
  -h "${PGHOST}" \
  -p "${PGPORT}" \
  -U "${PGUSER}" \
  | gzip > "${FILE}"

echo "[$(date)] pg_dumpall done, file: ${FILE}"

# 只保留 7 天備份，可自行調整
find "${BACKUP_DIR}" -type f -mtime +7 -name "*.sql.gz" -delete

echo "[$(date)] backup job finished"
