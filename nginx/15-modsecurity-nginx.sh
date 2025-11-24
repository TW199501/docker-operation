#!/usr/bin/env bash
# ================================================
# 編譯 15-modsecurity-nginx.sh
# 版本：v1.5（整合 UFW 基線；update 腳本可選同步 UFW）
# 說明：安裝 libModSecurity v3 + OWASP CRS，並編譯/載入
# ngx_http_modsecurity_module.so（動態模組）
# 適用：基礎WAF
# 日期：2025-10-03
# ===============================================
set -euo pipefail

# ---------- 可調 ----------
BUILD_DIR="${BUILD_DIR:-/home/nginx_build_geoip2}"
MODSEC_WORK="${BUILD_DIR}/modsec_build"
NGX_MODULES_DIR="/usr/lib/nginx/modules"
MODSEC_DIR="/etc/nginx/modsecurity"
CONF_D_DIR="/etc/nginx/conf.d"

# ---------- 需 root ----------
if [ "$(id -u)" -ne 0 ]; then
  echo "請用 root 執行: sudo bash 15-modsecurity-nginx.sh"
  exit 1
fi

echo "==> 準備建置目錄：$MODSEC_WORK"
rm -rf "$MODSEC_WORK"
mkdir -p "$MODSEC_WORK"

# 1) 安裝 libmodsecurity v3 + CRS（優先用套件)
echo "==> 安裝 libModSecurity v3 優先使用發行版套件"
if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -yq
  apt-get install -yq libmodsecurity3 libmodsecurity-dev modsecurity-crs git build-essential curl
elif command -v dnf >/dev/null 2>&1; then
  dnf -y install mod_security mod_security-devel git gcc make curl
  dnf -y install mod_security_crs || true
elif command -v yum >/dev/null 2>&1; then
  yum -y install mod_security mod_security-devel git gcc make curl
  yum -y install mod_security_crs || true
elif command -v apk >/dev/null 2>&1; then
  apk add --no-cache modsecurity modsecurity-dev modsecurity-rules-owasp-crs git build-base curl
else
  echo "!! 無法偵測套件管理器。請先手動安裝 libmodsecurity v3 (runtime+dev)、git、編譯工具後再跑本腳本。"
  exit 1
fi

# 確認 libmodsecurity 存在
if ! ldconfig -p 2>/dev/null | grep -qi 'libmodsecurity\.so'; then
  echo "!! 找不到 libmodsecurity(libmodsecurity.so)。請確認 libmodsecurity 已安裝（含 -dev）。"
  exit 1
fi

# 2) 取得 ModSecurity-nginx 連接器
echo "==> 取得 ModSecurity-nginx 連接器"
git clone --depth=1 https://github.com/owasp-modsecurity/ModSecurity-nginx.git \
  "${MODSEC_WORK}/ModSecurity-nginx"

# 3) 準備對應版本的 Nginx 原始碼
echo "==> 準備對應版本 Nginx 原始碼（用於編譯動態模組）"
NGINX_VER="$(nginx -v 2>&1 | sed -n 's/^nginx version: nginx\///p')"
[ -z "$NGINX_VER" ] && { echo "!! 無法取得 nginx 版本"; exit 1; }

NGX_SRC="${BUILD_DIR}/nginx-${NGINX_VER}"
if [ ! -d "$NGX_SRC" ]; then
  echo "   下載 nginx-${NGINX_VER} 原始碼..."
  mkdir -p "$BUILD_DIR"
  (
    cd "$BUILD_DIR" && \
    curl -fSLo "nginx-${NGINX_VER}.tar.gz" "http://nginx.org/download/nginx-${NGINX_VER}.tar.gz" && \
    tar -xzf "nginx-${NGINX_VER}.tar.gz"
  )
fi

# 抓已安裝 nginx 的 configure 參數，去掉可能已失效的來源路徑參數
echo "==> 讀取目前 nginx 的 configure 參數"
NGX_ARGS="$(nginx -V 2>&1 | sed -n 's/^.*configure arguments: //p')"
[ -z "$NGX_ARGS" ] && { echo "!! 無法取得 configure arguments"; exit 1; }
NGX_ARGS_CLEAN="$(echo "$NGX_ARGS" \
  | sed -E 's/--with-openssl=[^ ]+//g; s/--with-pcre=[^ ]+//g; s/--with-zlib=[^ ]+//g; s/[[:space:]]+/ /g')"

# 4) 只為動態模組重新 configure + make modules
echo "==> 以目前參數重新 configure 僅建置 modules 加入 ModSecurity 連接器"
cd "$NGX_SRC"
make clean || true
CONFIG_CMD="./configure $NGX_ARGS_CLEAN --add-dynamic-module=\"${MODSEC_WORK}/ModSecurity-nginx\""
echo "    執行：$CONFIG_CMD"
eval "$CONFIG_CMD"
make modules -j"$(nproc)"

# 安裝 .so
echo "==> 安裝 ngx_http_modsecurity_module.so -> ${NGX_MODULES_DIR}"
install -d -m 0755 "${NGX_MODULES_DIR}"
if [ -f "objs/ngx_http_modsecurity_module.so" ]; then
  install -m 0755 "objs/ngx_http_modsecurity_module.so" "${NGX_MODULES_DIR}/"
else
  echo "!! 編譯失敗，找不到 objs/ngx_http_modsecurity_module.so"
  exit 1
fi

# 5) modules 載入（與 10-build-nginx.sh 保持一致：/etc/nginx/modules/*.conf）
echo "==> 更新 /etc/nginx/modules/00-load-modules.conf"
mkdir -p /etc/nginx/modules
MODS_FILE="/etc/nginx/modules/00-load-modules.conf"
if ! grep -q 'ngx_http_modsecurity_module.so' "$MODS_FILE" 2>/dev/null; then
  echo "load_module ${NGX_MODULES_DIR}/ngx_http_modsecurity_module.so;" >> "$MODS_FILE"
fi

# 確保 /etc/nginx/nginx.conf 會載入 /etc/nginx/modules/*.conf（10-build 已處理，這裡再保險一次）
if ! grep -qE '^[[:space:]]*include[[:space:]]+/etc/nginx/modules/\*\.conf;?' /etc/nginx/nginx.conf; then
  sed -i '1i include /etc/nginx/modules/*.conf;' /etc/nginx/nginx.conf
fi

# ---------- 6) 佈署 ModSecurity + CRS 設定 ----------
echo "==> 佈署 ModSecurity 與 CRS 設定"
install -d -m 0755 "$MODSEC_DIR"

LOG_DIR="/var/log/modsecurity"
AUDIT_LOG="$LOG_DIR/audit.log"
install -d -m 0755 "$LOG_DIR"
touch "$AUDIT_LOG"

# 解析「目前生效」的 nginx 主設定（若 master 以 -c 啟動，沿用同一路徑）
ACTIVE_CFG="/etc/nginx/nginx.conf"
MPID=""
if command -v pgrep >/dev/null 2>&1; then
  MPID="$(pgrep -f 'nginx: master process' | head -n1 || true)"
fi
[ -n "$MPID" ] || MPID="$(ps ax -o pid=,cmd= | awk '/nginx: master process/{print $1; exit}')"
if [ -n "${MPID:-}" ] && [ -r "/proc/$MPID/cmdline" ]; then
  CMD="$(tr '\0' ' ' </proc/"$MPID"/cmdline)"
  if grep -q -- ' -c ' <<<"$CMD"; then
    ACTIVE_CFG="$(sed -n 's/.* -c \([^ ]\+\).*/\1/p' <<<"$CMD")"
  fi
fi

# 依 ACTIVE_CFG 抓執行 user（預設 www-data）
RUN_USER="$(awk '/^\s*user\s+/{print $2}' "$ACTIVE_CFG" 2>/dev/null | tr -d ' ;' | head -n1 || true)"
[ -z "$RUN_USER" ] && RUN_USER="www-data"
chown "$RUN_USER:$RUN_USER" "$AUDIT_LOG" 2>/dev/null || true
install -d -m 0750 -o "$RUN_USER" -g "$RUN_USER" /var/cache/modsecurity

# 尋找 modsecurity.conf 樣板；找不到就寫最小可用設定
CORE_CONF="$MODSEC_DIR/modsecurity.conf"
TEMPLATES=(
  /etc/modsecurity/modsecurity.conf-recommended
  /usr/local/etc/modsecurity.conf-recommended
  /usr/share/modsecurity-crs/modsecurity.conf-recommended
  /usr/share/doc/modsecurity-crs/examples/modsecurity.conf-recommended
)
FOUND_TEMPLATE=""
for t in "${TEMPLATES[@]}"; do
  [ -f "$t" ] && { FOUND_TEMPLATE="$t"; break; }
done

if [ -n "$FOUND_TEMPLATE" ]; then
  echo "   - 使用樣板：$FOUND_TEMPLATE"
  cp -f "$FOUND_TEMPLATE" "$CORE_CONF"
  sed -i 's/^\s*SecRuleEngine\s\+.*/SecRuleEngine On/' "$CORE_CONF"
else
  echo "   - 找不到樣板 寫入最小可用設定 fallback"
  cat > "$CORE_CONF" <<'CONF'
SecRuleEngine On
SecRequestBodyAccess On
SecResponseBodyAccess Off
SecTmpDir /tmp
SecDataDir /var/cache/modsecurity
SecAuditEngine RelevantOnly
SecAuditLog /var/log/modsecurity/audit.log
SecAuditLogFormat JSON
SecAuditLogType Serial
SecAuditLogParts ABCEFHKZ
SecArgumentSeparator &
SecResponseBodyLimit 524288
SecRequestBodyLimit 268435456
SecRequestBodyNoFilesLimit 131072
SecPcreMatchLimit 100000
SecPcreMatchLimitRecursion 100000
CONF
fi

# 偵測/連結 CRS，並保證 crs-setup.conf 與 rules 存在（避免「Not able to open file」）
CRS_DIR=""
for d in /usr/share/modsecurity-crs /etc/modsecurity/crs /usr/local/share/modsecurity-crs; do
  if [ -d "$d" ]; then CRS_DIR="$d"; break; fi
done

if [ -n "$CRS_DIR" ]; then
  echo "   - 偵測到 CRS: $CRS_DIR"
  ln -sfn "$CRS_DIR" "$MODSEC_DIR/crs"
  if [ -f "$MODSEC_DIR/crs/crs-setup.conf.example" ] && [ ! -f "$MODSEC_DIR/crs/crs-setup.conf" ]; then
    cp "$MODSEC_DIR/crs/crs-setup.conf.example" "$MODSEC_DIR/crs/crs-setup.conf"
  fi
  # 如果還是沒有（某些包不含 example），寫一個最小檔避免錯誤
  [ -f "$MODSEC_DIR/crs/crs-setup.conf" ] || echo "# minimal CRS setup" > "$MODSEC_DIR/crs/crs-setup.conf"
  # 檢查 rules 目錄
  if [ ! -d "$MODSEC_DIR/crs/rules" ]; then
    echo "⚠️  未發現 $MODSEC_DIR/crs/rules 請確認 modsecurity-crs 是否完整安裝"
  fi
else
  echo "   - 未找到 CRS 之後可安裝 modsecurity-crs 套件再重載"
fi

# 主引入檔（供 modsecurity_rules_file 指向）
MAIN_CONF="$MODSEC_DIR/main.conf"
{
  echo "Include $CORE_CONF"
  if [ -n "$CRS_DIR" ]; then
    echo "Include $MODSEC_DIR/crs/crs-setup.conf"
    echo "Include $MODSEC_DIR/crs/rules/*.conf"
  fi
  # 建一份範例本地例外（存在即可；可自行修改/清空）
  echo "Include $MODSEC_DIR/local-exclusions.conf"
} > "$MAIN_CONF"

cat > "$MODSEC_DIR/local-exclusions.conf" <<'EXC'
# 範例：排除 192.168.0.0/16 的 920440 規則（請依需求調整/刪除）
SecRule REMOTE_ADDR "@ipMatch 192.168.0.0/16" \
    "id:400000,phase:2,nolog,pass,ctl:ruleRemoveById=920440"
EXC

# 在 /etc/nginx/conf.d 啟用（你的 /etc/nginx/nginx.conf / 或 WebUI 的 http{} 需有 include conf.d/*.conf）
install -d -m 0755 "$CONF_D_DIR"
cat > "$CONF_D_DIR/modsecurity-enable.conf" <<'NG'
# 啟用 ModSecurity (http 區塊）
modsecurity on;
modsecurity_rules_file /etc/nginx/modsecurity/main.conf;
NG

echo "   - 主設定：$MAIN_CONF"
echo "   - 啟用片段：$CONF_D_DIR/modsecurity-enable.conf"

# ---------- 7) 不執行 nginx -t，只嘗試 reload ----------
echo "==> 嘗試重載 Nginx不執行 nginx -t"
if [ -n "${MPID:-}" ] && [ -f "$ACTIVE_CFG" ]; then
  if nginx -s reload; then
    echo "[OK] 已透過目前 master 進程重載 nginx"
  else
    echo "[WARN] 透過 master 進程重載失敗，請手動檢查 nginx"
  fi
else
  if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet nginx; then
    if systemctl reload nginx; then
      echo "[OK] 已透過 systemctl reload nginx"
    else
      echo "[WARN] systemctl reload nginx 失敗，改用 nginx -s reload"
      nginx -s reload || echo "[WARN] nginx -s reload 失敗，請手動檢查 nginx"
    fi
  else
    nginx -s reload || nginx || echo "[WARN] nginx reload/start 失敗，請手動檢查 nginx 配置"
  fi
fi

echo
echo "✅ 完成 ModSecurity v3 + CRS 啟用。"
echo "   - 模組：${NGX_MODULES_DIR}/ngx_http_modsecurity_module.so(已自動載入）"
echo "   - 核心設定：${CORE_CONF}"
echo "   - CRS:${CRS_DIR:-未安裝，已跳過 Include}"
echo "   - 包含檔：${MAIN_CONF}"
echo "   - Nginx 啟用片段：${CONF_D_DIR}/modsecurity-enable.conf"
echo
echo "   若你日後用 nginxWebUI 的獨立 nginx.conf(例如 -c /home/nginxWebUI/nginx.conf）"
echo "   請確認該 http{} 內有：  include /etc/nginx/conf.d/*.conf;  以讀取上面的啟用片段。"
