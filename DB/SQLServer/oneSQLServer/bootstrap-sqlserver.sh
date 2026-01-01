#!/bin/sh
# 使用 docker compose v2 自動設定 SQL Server 容器

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"
COMPOSE_FILE_URL="https://raw.githubusercontent.com/TW199501/docker-operation/main/SQLServer/docker-compose.yml"
ENV_FILE="${SCRIPT_DIR}/.env"
DEFAULT_BASE_DIR="$(pwd)"
DEFAULT_CONTAINER_NAME="mssql2022"
DEFAULT_HOST_PORT="1433or自訂"
DEFAULT_COLLATION="Chinese_Taiwan_Stroke_CI_AS"
DEFAULT_CPU_LIMIT=""
DEFAULT_CPU_RESERVE=""
DEFAULT_MEM_LIMIT=""
DATA_DIR="${DATA_DIR:-"$SCRIPT_DIR/data"}"
LOG_DIR="${LOG_DIR:-"$SCRIPT_DIR/log"}"
BACKUP_DIR="${BACKUP_DIR:-"$SCRIPT_DIR/backup"}"
DEFAULT_CERT_DIR="${SCRIPT_DIR}/cert"
DEFAULT_CERT_MODE="ro"
DEFAULT_DNS=""
DEFAULT_PID="Developer"

info()  { printf "[INFO] %s\n" "$*"; }
warn()  { printf "[WARN] %s\n" "$*" >&2; }
error() { printf "[ERROR] %s\n" "$*" >&2; }

ask_value() {
  var_name="$1"
  prompt="$2"
  default_value="${3:-}"
  while :; do
    if [ -n "$default_value" ]; then
      printf "%s [%s]: " "$prompt" "$default_value"
    else
      printf "%s: " "$prompt"
    fi
    IFS= read -r answer || answer=""
    if [ -z "$answer" ] && [ -n "$default_value" ]; then
      answer="$default_value"
    fi
    if [ -n "$answer" ]; then
      eval "$var_name=\"\$answer\""
      return 0
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
      *) printf "請輸入 y 或 n。\n" ;;
    esac
  done
}

# --- POSIX-safe ask_secret: returns value via stdout (no eval) ---
ask_secret() {
  prompt="$1"
  printf "%s: " "$prompt"
  if command -v stty >/dev/null 2>&1; then
    stty -echo
    IFS= read -r secret || secret=""
    stty echo
    printf "\n"
  else
    IFS= read -r secret || secret=""
  fi
  printf '%s' "$secret"
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

# --- Detect docker compose (v2 subcommand or plugin) ---
detect_compose() {
  if command -v docker >/dev/null 2>&1; then
    if docker compose version >/dev/null 2>&1; then
      COMPOSE_BIN="docker"
      COMPOSE_SUBCMD="compose"
      return 0
    fi
  fi
  if command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_BIN="docker-compose"
    COMPOSE_SUBCMD=""
    return 0
  fi
  error "找不到 docker compose，請安裝 Docker Desktop 或 docker-compose。"
  exit 1
}

# --- Resources heuristics for defaults ---
detect_host_resources() {
  HOST_CORES="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"
  if [ -z "$HOST_CORES" ] || [ "$HOST_CORES" -lt 1 ]; then
    HOST_CORES=1
  fi

  if [ "$HOST_CORES" -gt 1 ]; then
    DEFAULT_CORE_COUNT=$((HOST_CORES - 1))
  else
    DEFAULT_CORE_COUNT=1
  fi

  CPU_LIMIT_VAL="$DEFAULT_CORE_COUNT"
  if [ "$CPU_LIMIT_VAL" -lt 1 ]; then
    CPU_LIMIT_VAL=1
  fi
  DEFAULT_CPU_LIMIT="${CPU_LIMIT_VAL}"

  # Memory in MB
  HOST_MEM_MB=""
  case "$(uname -s)" in
    Linux)
      if [ -r /proc/meminfo ]; then
        HOST_MEM_KB="$(awk '/MemTotal:/ {print $2}' /proc/meminfo)"
        HOST_MEM_MB=$((HOST_MEM_KB / 1024))
      fi
      ;;
    Darwin)
      HOST_MEM_BYTES="$(sysctl -n hw.memsize 2>/dev/null || echo 0)"
      HOST_MEM_MB=$((HOST_MEM_BYTES / 1024 / 1024))
      ;;
    *)
      HOST_MEM_MB=4096
      ;;
  esac

  if [ -z "$HOST_MEM_MB" ] || [ "$HOST_MEM_MB" -lt 2048 ]; then
    HOST_MEM_MB=4096
  fi

  # Use 3/4 of host memory but keep 2G headroom; min 2G
  if [ "$HOST_MEM_MB" -gt 8192 ]; then
    DEFAULT_RAM_SIZE=$((HOST_MEM_MB - 2048))
  else
    DEFAULT_RAM_SIZE=$((HOST_MEM_MB * 3 / 4))
  fi

  if [ "$DEFAULT_RAM_SIZE" -lt 2048 ]; then
    DEFAULT_RAM_SIZE=2048
  fi

  DEFAULT_MEM_LIMIT_GB=$(((DEFAULT_RAM_SIZE + 1023) / 1024))
  if [ "$DEFAULT_MEM_LIMIT_GB" -lt 2 ]; then
    DEFAULT_MEM_LIMIT_GB=2
  fi
  DEFAULT_MEM_LIMIT="${DEFAULT_MEM_LIMIT_GB}G"
}

main() {
  require_command curl
  require_command sed
  require_command awk
  require_command grep

  detect_compose
  detect_host_resources

  info "=== SQL Server Docker Compose 初始化 ==="

  ask_value BASE_DIR "請輸入安裝基底目錄 (存放 data/log/backup/cert)" "$DEFAULT_BASE_DIR"
  BASE_DIR="${BASE_DIR%/}"

  DATA_DIR="${BASE_DIR}/data"
  LOG_DIR="${BASE_DIR}/log"
  BACKUP_DIR="${BASE_DIR}/backup"
  CERT_DIR="${BASE_DIR}/cert"

  ensure_directory "$DATA_DIR"  "0775"
  ensure_directory "$LOG_DIR"   "0775"
  ensure_directory "$BACKUP_DIR" "0775"
  ensure_directory "$CERT_DIR"  "0755"

  ask_value CONTAINER_NAME "請輸入容器名稱" "$DEFAULT_CONTAINER_NAME"
  ask_value HOST_PORT "請輸入主機對外埠 (1433 或自訂)" "$DEFAULT_HOST_PORT"
  ask_value COLLATION "請輸入資料庫排序規則 (Collation)" "$DEFAULT_COLLATION"

  # --- secret (POSIX-safe) ---
  MSSQL_PASSWORD="$(ask_secret "請輸入 MSSQL_SA_PASSWORD")"
  if [ ${#MSSQL_PASSWORD} -lt 12 ]; then
    error "密碼長度需至少 12，請重新執行。"
    exit 1
  fi

  ask_yes_no USE_CERT "是否掛載 TLS 憑證目錄 (${CERT_DIR})" "n"
  if [ "$USE_CERT" = "y" ]; then
    ask_value CERT_MODE "請輸入憑證掛載模式 (ro / rw)" "$DEFAULT_CERT_MODE"
  else
    CERT_MODE=""
  fi

  ask_value CPU_LIMIT "請輸入 CPU 限制 (核心數，如 1、2；留空採預設)" "$DEFAULT_CPU_LIMIT"
  ask_value CPU_RESERVE "請輸入 CPU 保留 (核心數；可留空)" "$DEFAULT_CPU_RESERVE"
  ask_value MEM_LIMIT "請輸入記憶體上限 (如 2G、4G；留空採預設)" "$DEFAULT_MEM_LIMIT"
  ask_value DNS_SERVERS "自訂 DNS (逗號分隔，如 1.1.1.1,8.8.8.8；可留空)" "$DEFAULT_DNS"
  ask_value PID_EDITION "MSSQL PID (Developer/Express/Standard/Enterprise)" "$DEFAULT_PID"

  # 下載 docker-compose.yml（若不存在）
  if [ ! -f "$COMPOSE_FILE" ]; then
    info "下載 docker-compose.yml..."
    curl -fsSL "$COMPOSE_FILE_URL" -o "$COMPOSE_FILE"
  else
    info "偵測到既有 docker-compose.yml，將沿用。"
  fi

  # 可選：chown 目錄給 mssql 預設 UID/GID
  if command -v chown >/dev/null 2>&1; then
    ask_yes_no SET_OWNERSHIP "是否將目錄擁有者設定為 10001:0 (mssql 預設)" "y"
    if [ "$SET_OWNERSHIP" = "y" ]; then
      # --- POSIX-safe: use positional parameters instead of arrays ---
      set -- "$DATA_DIR" "$LOG_DIR" "$BACKUP_DIR"
      if [ "$CERT_DIR" = "$DEFAULT_CERT_DIR" ]; then
        set -- "$@" "$CERT_DIR"
      else
        info "憑證目錄為自訂路徑，略過 chown：$CERT_DIR"
      fi
      if [ "$#" -gt 0 ]; then
        chown -R 10001:0 "$@"
      fi
    fi
  fi

  # 既有 .env 是否覆寫
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
MSSQL_PID=$PID_EDITION
MSSQL_COLLATION=$COLLATION
MSSQL_DATA_DIR=$DATA_DIR
MSSQL_LOG_DIR=$LOG_DIR
MSSQL_BACKUP_DIR=$BACKUP_DIR
MSSQL_CERT_DIR=$CERT_DIR
HOST_PORT=$HOST_PORT
CPU_LIMIT=$CPU_LIMIT
CPU_RESERVE=$CPU_RESERVE
MEM_LIMIT=$MEM_LIMIT
CERT_MODE=$CERT_MODE
DNS_SERVERS=$DNS_SERVERS
EOF

  info "已寫入 .env：$ENV_FILE"

  ask_yes_no START_SERVICE "是否立即執行 docker compose up -d" "y"
  if [ "$START_SERVICE" = "y" ]; then
    if [ -n "${COMPOSE_SUBCMD:-}" ]; then
      "$COMPOSE_BIN" "$COMPOSE_SUBCMD" -f "$COMPOSE_FILE" up -d
    else
      "$COMPOSE_BIN" -f "$COMPOSE_FILE" up -d
    fi
    info "已啟動 SQL Server 容器。"
  else
    info "已建立 .env，可手動執行 docker compose up -d。"
  fi

  info "流程完成。請妥善保存 SA 密碼，並將憑證掛載於 $CERT_DIR。"
}

main "$@"
