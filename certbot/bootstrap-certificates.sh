#!/bin/sh
# shellcheck disable=SC2039

set -eu

DEFAULT_CERTBOT_BASE="/opt/certbot"
DEFAULT_ACME_BASE="/opt/acme.sh"
LOG_DIR="/var/log"

error() {
  printf "[ERROR] %s\n" "$1" >&2
}

info() {
  printf "[INFO] %s\n" "$1"
}

title() {
  printf "\n==== %s ====\n" "$1"
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
    [Yy]) prompt_suffix="[Y/n]" ; default_char="y" ;;
    [Nn]) prompt_suffix="[y/N]" ; default_char="n" ;;
    *) prompt_suffix="[y/n]" ; default_char="" ;;
  esac
  while :; do
    printf "%s %s: " "$prompt" "$prompt_suffix"
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

append_cron() {
  cron_expr="$1"
  cron_cmd="$2"
  if ! command -v crontab >/dev/null 2>&1; then
    error "系統未安裝 crontab，請先安裝 cron 後再手動加入排程。"
    return 1
  fi
  tmp_file="$(mktemp)"
  if ! crontab -l >"$tmp_file" 2>/dev/null; then
    : >"$tmp_file"
  fi
  if grep -F "$cron_cmd" "$tmp_file" >/dev/null 2>&1; then
    info "排程已存在，略過新增。"
    rm -f "$tmp_file"
    return 0
  fi
  printf "%s %s\n" "$cron_expr" "$cron_cmd" >>"$tmp_file"
  crontab "$tmp_file"
  rm -f "$tmp_file"
  info "已更新 crontab。"
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    error "找不到指令: $1"
    exit 1
  fi
}

require_command docker

title "選擇憑證簽發方式"
printf "1) Certbot + Cloudflare DNS\n2) acme.sh + Cloudflare DNS\n"
ask_required METHOD "請輸入選項" "1"

case "$METHOD" in
  1)
    title "Certbot 設定"
    ask_default CERTBOT_BASE "Certbot 基底目錄" "$DEFAULT_CERTBOT_BASE"
    CERTBOT_CERT_DIR="$CERTBOT_BASE/certs"
    CERTBOT_LIB_DIR="$CERTBOT_BASE/certs-lib"
    CF_INI_PATH="$CERTBOT_BASE/cloudflare.ini"

    ensure_directory "$CERTBOT_CERT_DIR" 700
    ensure_directory "$CERTBOT_LIB_DIR" 700

    ask_required ROOT_DOMAIN "主要網域 (例如 example.com)" ""
    ask_yes_no ADD_WILDCARD "是否同時申請 Wildcard (*.domain)" "y"
    if [ "$ADD_WILDCARD" = "y" ]; then
      ALT_DOMAIN="*.${ROOT_DOMAIN}"
    else
      ask_default ALT_DOMAIN "額外網域 (可留空)" ""
    fi

    ask_default PROPAGATION_SECONDS "DNS 佈署等待秒數" "120"

    title "Cloudflare 認證資訊"
    ask_yes_no USE_API_TOKEN "使用 API Token (推薦)" "y"
    if [ "$USE_API_TOKEN" = "y" ]; then
      ask_secret CF_TOKEN "請輸入 Cloudflare API Token"
      cat <<EOF >"$CF_INI_PATH"
dns_cloudflare_api_token = ${CF_TOKEN}
EOF
    else
      ask_required CF_EMAIL "Cloudflare 帳號 Email" ""
      ask_secret CF_API_KEY "Cloudflare Global API Key"
      cat <<EOF >"$CF_INI_PATH"
dns_cloudflare_email = ${CF_EMAIL}
dns_cloudflare_api_key = ${CF_API_KEY}
EOF
    fi
    chmod 600 "$CF_INI_PATH"
    info "已建立 $CF_INI_PATH"

    title "執行 Certbot 首次申請"
    DOCKER_ARGS="docker run --rm \
      -v \"${CERTBOT_CERT_DIR}:/etc/letsencrypt\" \
      -v \"${CERTBOT_LIB_DIR}:/var/lib/letsencrypt\" \
      -v \"${CF_INI_PATH}:/cloudflare.ini:ro\" \
      certbot/dns-cloudflare certonly \
      --dns-cloudflare \
      --dns-cloudflare-credentials /cloudflare.ini \
      --dns-cloudflare-propagation-seconds ${PROPAGATION_SECONDS} \
      -d ${ROOT_DOMAIN}"
    if [ -n "$ALT_DOMAIN" ]; then
      DOCKER_ARGS="$DOCKER_ARGS \
      -d ${ALT_DOMAIN}"
    fi

    sh -c "$DOCKER_ARGS"

    LIVE_DIR="$CERTBOT_CERT_DIR/live/$ROOT_DOMAIN"
    if [ -d "$LIVE_DIR" ]; then
      info "憑證已產生於 $LIVE_DIR"
    else
      error "未找到 $LIVE_DIR，請檢查指令輸出。"
    fi

    ask_yes_no DO_DEPLOY_COPY "是否將 fullchain/privkey 複製到其他目錄" "n"
    if [ "$DO_DEPLOY_COPY" = "y" ]; then
      ask_required DEPLOY_DIR "目標目錄" ""
      ensure_directory "$DEPLOY_DIR" 700
      if [ -f "$LIVE_DIR/fullchain.pem" ] && [ -f "$LIVE_DIR/privkey.pem" ]; then
        cp "$LIVE_DIR/fullchain.pem" "$DEPLOY_DIR/fullchain.pem"
        cp "$LIVE_DIR/privkey.pem" "$DEPLOY_DIR/privkey.pem"
        chmod 600 "$DEPLOY_DIR/privkey.pem"
        chmod 644 "$DEPLOY_DIR/fullchain.pem"
        info "已將憑證複製到 $DEPLOY_DIR"
      else
        error "缺少 fullchain.pem 或 privkey.pem，無法複製。"
      fi
    fi

    title "加入定期續期排程"
    ask_default CRON_EXPR "Cron 表達式" "30 3 * * *"
    CRON_CMD="docker run --rm -v \"${CERTBOT_CERT_DIR}:/etc/letsencrypt\" -v \"${CERTBOT_LIB_DIR}:/var/lib/letsencrypt\" -v \"${CF_INI_PATH}:/cloudflare.ini:ro\" certbot/dns-cloudflare renew >> ${LOG_DIR}/certbot-renew.log 2>&1"
    append_cron "$CRON_EXPR" "$CRON_CMD" || true
    info "Certbot 流程完成。"
    ;;
  2)
    title "acme.sh 設定"
    ask_default ACME_BASE "acme.sh 基底目錄" "$DEFAULT_ACME_BASE"
    ensure_directory "$ACME_BASE" 700
    ACME_ENV_FILE="$ACME_BASE/cloudflare.env"

    ask_required ROOT_DOMAIN "主要網域 (例如 example.com)" ""
    ask_yes_no ADD_WILDCARD "是否同時申請 Wildcard (*.domain)" "y"
    if [ "$ADD_WILDCARD" = "y" ]; then
      ALT_DOMAIN="*.${ROOT_DOMAIN}"
    else
      ask_default ALT_DOMAIN "額外網域 (可留空)" ""
    fi

    ask_required ACME_EMAIL "通知 Email" ""

    title "Cloudflare 認證資訊"
    ask_yes_no USE_API_TOKEN "使用 API Token (推薦)" "y"
    if [ "$USE_API_TOKEN" = "y" ]; then
      ask_secret CF_TOKEN "Cloudflare API Token"
      cat <<EOF >"$ACME_ENV_FILE"
CF_Token=${CF_TOKEN}
EOF
    else
      ask_required CF_EMAIL "Cloudflare 帳號 Email" ""
      ask_secret CF_API_KEY "Cloudflare Global API Key"
      cat <<EOF >"$ACME_ENV_FILE"
CF_Key=${CF_API_KEY}
CF_Email=${CF_EMAIL}
EOF
    fi
    chmod 600 "$ACME_ENV_FILE"
    info "已建立 $ACME_ENV_FILE"

    title "註冊 acme.sh 帳號"
    docker run --rm -it \
      -v "$ACME_BASE:/acme.sh" \
      --env-file "$ACME_ENV_FILE" \
      neilpang/acme.sh --register-account -m "$ACME_EMAIL" || true

    title "執行 acme.sh 首次申請"
    ISSUE_CMD="docker run --rm -it \
      -v ${ACME_BASE}:/acme.sh \
      --env-file ${ACME_ENV_FILE} \
      neilpang/acme.sh --issue \
      --dns dns_cf \
      -d ${ROOT_DOMAIN}"
    if [ -n "$ALT_DOMAIN" ]; then
      ISSUE_CMD="$ISSUE_CMD \
      -d ${ALT_DOMAIN}"
    fi
    sh -c "$ISSUE_CMD"

    ACME_CERT_DIR="$ACME_BASE/${ROOT_DOMAIN}"
    if [ -d "$ACME_CERT_DIR" ]; then
      info "憑證已產生於 $ACME_CERT_DIR"
    else
      error "未找到 $ACME_CERT_DIR，請檢查指令輸出。"
    fi

    ask_yes_no DO_INSTALL "是否使用 acme.sh --install-cert 複製到固定路徑" "y"
    if [ "$DO_INSTALL" = "y" ]; then
      ask_required DEPLOY_DIR "部署目錄" ""
      ensure_directory "$DEPLOY_DIR" 700
      INSTALL_CMD="docker run --rm -it \
        -v ${ACME_BASE}:/acme.sh \
        --env-file ${ACME_ENV_FILE} \
        neilpang/acme.sh --install-cert -d ${ROOT_DOMAIN} \
        --cert-file ${DEPLOY_DIR}/cert.pem \
        --key-file ${DEPLOY_DIR}/privkey.pem \
        --fullchain-file ${DEPLOY_DIR}/fullchain.pem"
      sh -c "$INSTALL_CMD"
      if [ -f "$DEPLOY_DIR/privkey.pem" ]; then
        chmod 600 "$DEPLOY_DIR/privkey.pem"
      fi
      if [ -f "$DEPLOY_DIR/fullchain.pem" ]; then
        chmod 644 "$DEPLOY_DIR/fullchain.pem"
      fi
      info "已部署憑證至 $DEPLOY_DIR"
    fi

    title "加入 acme.sh 定期檢查排程"
    ask_default CRON_EXPR "Cron 表達式" "15 3 * * *"
    CRON_CMD="docker run --rm -v ${ACME_BASE}:/acme.sh --env-file ${ACME_ENV_FILE} neilpang/acme.sh --cron >> ${LOG_DIR}/acme-cron.log 2>&1"
    append_cron "$CRON_EXPR" "$CRON_CMD" || true
    info "acme.sh 流程完成。"
    ;;
  *)
    error "未知的選項：$METHOD"
    exit 1
    ;;
esac

info "全部流程完成，請檢查上述訊息確認是否有錯誤。"
