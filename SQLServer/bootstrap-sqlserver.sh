#!/bin/sh
# Automate SQL Server container setup using docker compose v2.

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"
COMPOSE_FILE_URL="https://raw.githubusercontent.com/TW199501/docker-operation/main/SQLServer/docker-compose.yml"
ENV_FILE="${SCRIPT_DIR}/.env"
DEFAULT_BASE_DIR="DEFAULT_BASE_DIR"
DEFAULT_CONTAINER_NAME="mssql2022-dev"
DEFAULT_HOST_PORT="1433"
DEFAULT_COLLATION="Chinese_Taiwan_Stroke_Count_100_CI_AS_SC_UTF8"
DEFAULT_CPU_LIMIT="4.0"
DEFAULT_CPU_RESERVE="2.0"
DEFAULT_MEM_LIMIT="12G"
DEFAULT_MEM_RESERVE="6G"
DEFAULT_TIMEZONE="Asia/Taipei"

error() {
  printf "[ERROR] %s\n" "$1" >&2
}

info() {
  printf "[INFO] %s\n" "$1"
}

ask_default() {
  var_name="$1"
  prompt="$2"
  default="$3"
  if [ -n "$default" ]; then
    printf "%s [%s]: " "$prompt" "$default"
  else
    printf "%s: " "$prompt"
  fi
  IFS= read -r input || input=""
  if [ -z "$input" ]; then
    input="$default"
  fi
  eval "$var_name=\"\$input\""
}

ask_required() {
  var_name="$1"
  prompt="$2"
  default_value="$3"
  while :; do
    ask_default "$var_name" "$prompt" "$default_value"
    eval "value=\${$var_name}"
    if [ -n "$value" ]; then
      break
    fi
    printf "值不得為空，請重新輸入。\n"
    default_value=""
  done
}

ask_yes_no() {
  var_name="$1"
  prompt="$2"
  default_answer="$3"
  case "$default_answer" in
    [Yy]) suffix="[Y/n]"; default_char="y" ;;
    [Nn]) suffix="[y/N]"; default_char="n" ;;
    *) suffix="[y/n]"; default_char="" ;;
  esac
  while :; do
    printf "%s %s: " "$prompt" "$suffix"
    IFS= read -r answer || answer=""
    if [ -z "$answer" ] && [ -n "$default_char" ]; then
      answer="$default_char"
    fi
    case "$answer" in
      [Yy]) eval "$var_name=\"y\""; return 0 ;;
      [Nn]) eval "$var_name=\"n\""; return 0 ;;
    esac
    printf "請輸入 y 或 n。\n"
  done
}

ask_secret() {
  var_name="$1"
  prompt="$2"
  printf "%s: " "$prompt"
  if command -v stty >/dev/null 2>&1; then
    stty -echo
    IFS= read -r secret || secret=""
    stty echo
    printf "\n"
  else
    IFS= read -r secret || secret=""
  fi
  eval "$var_name=\"\$secret\""
}

ensure_directory() {
  dir_path="$1"
  perms="$2"
  if [ ! -d "$dir_path" ]; then
    mkdir -p "$dir_path"
  fi
  if [ -n "$perms" ]; then
    chmod "$perms" "$dir_path"
  fi
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    error "找不到指令: $1"
    exit 1
  fi
}

select_compose_command() {
  if docker compose version >/dev/null 2>&1; then
    COMPOSE_BIN="docker"
    COMPOSE_SUBCMD="compose"
    info "使用 docker compose (v2)。"
  elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_BIN="docker-compose"
    COMPOSE_SUBCMD=""
    info "偵測到 docker-compose (v1)，將以此執行。"
  else
    error "找不到 docker compose 指令，請先安裝 Docker Compose v2。"
    exit 1
  fi
}

generate_password() {
  length="$1"
  SPECIAL="!@#$%^&*-_=+"
  if ! command -v python3 >/dev/null 2>&1; then
    error "需要 python3 來產生隨機密碼。"
    exit 1
  fi
  python3 <<PY
import secrets
import string

length = int(${length})
special = "${SPECIAL}"
alphabet = string.ascii_letters + string.digits + special

while True:
    pwd = ''.join(secrets.choice(alphabet) for _ in range(length))
    if (any(c.islower() for c in pwd)
            and any(c.isupper() for c in pwd)
            and any(c.isdigit() for c in pwd)
            and any(c in special for c in pwd)):
        print(pwd)
        break
PY
}

require_command docker
select_compose_command

if [ ! -f "$COMPOSE_FILE" ]; then
  info "未找到 docker-compose.yml，從遠端載入範例。"
  if ! curl -fsSL "$COMPOSE_FILE_URL" -o "$COMPOSE_FILE"; then
    error "下載 docker-compose.yml 失敗：$COMPOSE_FILE_URL"
    exit 1
  fi
  info "已下載 $COMPOSE_FILE"
else
  ask_yes_no REFRESH_COMPOSE "需要重新下載 docker-compose.yml 嗎" "n"
  if [ "$REFRESH_COMPOSE" = "y" ]; then
    if ! curl -fsSL "$COMPOSE_FILE_URL" -o "$COMPOSE_FILE"; then
      error "重新下載 docker-compose.yml 失敗：$COMPOSE_FILE_URL"
      exit 1
    fi
    info "已更新 $COMPOSE_FILE"
  fi
fi

ask_default BASE_DIR "主機資料根目錄" "$DEFAULT_BASE_DIR"
DATA_DIR="$BASE_DIR/sql_data"
LOG_DIR="$BASE_DIR/sql_log"
BACKUP_DIR="$BASE_DIR/sql_backup"
CERT_DIR="$BASE_DIR/certs"

ask_default CONTAINER_NAME "容器名稱" "$DEFAULT_CONTAINER_NAME"
ask_default HOST_PORT "主機對外 Port" "$DEFAULT_HOST_PORT"
ask_default COLLATION "資料庫排序 (Collation)" "$DEFAULT_COLLATION"
ask_default CPU_LIMIT "CPU 上限" "$DEFAULT_CPU_LIMIT"
ask_default CPU_RESERVE "CPU 保留" "$DEFAULT_CPU_RESERVE"
ask_default MEM_LIMIT "記憶體上限" "$DEFAULT_MEM_LIMIT"
ask_default MEM_RESERVE "記憶體保留" "$DEFAULT_MEM_RESERVE"
ask_default TIMEZONE "容器時區" "$DEFAULT_TIMEZONE"

ask_yes_no GEN_PWD "是否自動產生 MSSQL_SA_PASSWORD" "y"
if [ "$GEN_PWD" = "y" ]; then
  ask_default PWD_LENGTH "密碼長度 (>=12)" "24"
  case "$PWD_LENGTH" in
    ''|*[!0-9]* )
      error "密碼長度需為數字。"; exit 1 ;;
    * )
      if [ "$PWD_LENGTH" -lt 12 ]; then
        error "密碼長度至少 12。"
        exit 1
      fi
      ;;
  esac
  MSSQL_PASSWORD="$(generate_password "$PWD_LENGTH")"
  info "已產生隨機 SA 密碼。"
else
  ask_secret MSSQL_PASSWORD "請輸入 MSSQL_SA_PASSWORD"
  if [ ${#MSSQL_PASSWORD} -lt 12 ]; then
    error "密碼長度需至少 12，請重新執行腳本。"
    exit 1
  fi
fi

info "建立/調整資料目錄權限"
ensure_directory "$DATA_DIR" 770
ensure_directory "$LOG_DIR" 770
ensure_directory "$BACKUP_DIR" 770
ensure_directory "$CERT_DIR" 750

if command -v chown >/dev/null 2>&1; then
  ask_yes_no SET_OWNERSHIP "是否將目錄擁有者設定為 10001:0 (mssql 預設)" "y"
  if [ "$SET_OWNERSHIP" = "y" ]; then
    chown -R 10001:0 "$DATA_DIR" "$LOG_DIR" "$BACKUP_DIR" "$CERT_DIR"
  fi
fi

if [ -f "$ENV_FILE" ]; then
  ask_yes_no OVERWRITE_ENV "偵測到既有 .env，是否覆寫" "n"
  if [ "$OVERWRITE_ENV" != "y" ]; then
    error ".env 已存在且選擇不覆寫，請手動更新。"
    exit 1
  fi
fi

cat >"$ENV_FILE" <<EOF
# Auto-generated by bootstrap-sqlserver.sh on $(date -Iseconds)
MSSQL_CONTAINER_NAME=$CONTAINER_NAME
MSSQL_SA_PASSWORD=$MSSQL_PASSWORD
MSSQL_PID=Developer
MSSQL_COLLATION=$COLLATION
MSSQL_AGENT_ENABLED=true
MSSQL_TLS_CIPHER_SUITES=TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256
TZ=$TIMEZONE
MSSQL_HOST_PORT=$HOST_PORT
MSSQL_DATA_DIR_HOST=$DATA_DIR
MSSQL_CERT_DIR_HOST=$CERT_DIR
MSSQL_LIMIT_CPU=$CPU_LIMIT
MSSQL_LIMIT_MEM=$MEM_LIMIT
MSSQL_RESERVE_CPU=$CPU_RESERVE
MSSQL_RESERVE_MEM=$MEM_RESERVE
EOF
chmod 600 "$ENV_FILE"
info "已寫入 $ENV_FILE"

printf "\n====== .env 摘要 ======\n"
printf "容器名稱: %s\n" "$CONTAINER_NAME"
printf "資料目錄: %s\n" "$DATA_DIR"
printf "證書目錄: %s\n" "$CERT_DIR"
printf "主機 Port: %s\n" "$HOST_PORT"
printf "=======================\n\n"

ask_yes_no START_SERVICE "是否立即執行 docker compose up -d" "y"
if [ "$START_SERVICE" = "y" ]; then
  if [ -n "$COMPOSE_SUBCMD" ]; then
    "${COMPOSE_BIN}" "${COMPOSE_SUBCMD}" -f "$COMPOSE_FILE" up -d
  else
    "${COMPOSE_BIN}" -f "$COMPOSE_FILE" up -d
  fi
  info "已啟動 SQL Server 容器。"
else
  info "已建立 .env，可手動執行 docker compose up -d。"
fi

info "流程完成。請妥善保存 SA 密碼，並將憑證掛載於 $CERT_DIR。"
