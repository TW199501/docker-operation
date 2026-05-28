#!/usr/bin/env bash
# =============================================================================
# CI 用:掃全 repo .env.example,檢查 $(...) 在白名單內、字面密碼擋下
# 規範:docs/conventions/env-naming.md
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/whitelist.sh
source "$SCRIPT_DIR/lib/whitelist.sh"

violations=0

# 字面密碼 heuristic
# 模式:PASSWORD-like key = 非空 / 非 $() 開頭 / 非引號開頭 / 8+ 字元 alphanum
# 排除已知的「明顯佔位」:your_xxx / xxx_here / xxx_placeholder
check_literal_password() {
  local file="$1"
  local line_no=0
  local local_violations=0
  while IFS= read -r line; do
    line_no=$((line_no + 1))
    # 跳過註解行
    [[ "$line" =~ ^[[:space:]]*# ]] && continue

    if [[ "$line" =~ ^[[:space:]]*([A-Z_]*(PASSWORD|PASSWD|SECRET|TOKEN|KEY)[A-Z_]*)=([^[:space:]#]+) ]]; then
      local key="${BASH_REMATCH[1]}"
      local val="${BASH_REMATCH[3]}"

      # 排除合規寫法
      [[ "$val" =~ ^\$\( ]] && continue        # $(...) 自動生成
      [[ "$val" =~ ^\" ]] && continue          # 引號值
      [[ "$val" =~ ^your_ ]] && continue       # your_xxx 佔位
      [[ "$val" =~ _here$ ]] && continue       # xxx_here 佔位
      [[ "$val" =~ placeholder ]] && continue  # placeholder

      # 排除 key=key 重複(也算佔位)
      [ "$val" = "$key" ] && continue

      # 排除短值(不像密碼)
      [ ${#val} -lt 8 ] && continue

      # 排除全 LFS_JWT_SECRET= 之類空值(已被前面 ^[^space#]+ 擋掉但保險)
      [ -z "$val" ] && continue

      # heuristic 命中
      echo "::error file=$file,line=$line_no::疑似硬編碼密碼:${key}=${val}"
      local_violations=$((local_violations + 1))
    fi
  done < "$file"
  return $local_violations
}

while IFS= read -r example; do
  echo "=== $example ==="

  # 1. 白名單
  if ! env_whitelist_scan "$example"; then
    violations=$((violations + 1))
  fi

  # 2. 字面密碼 heuristic
  check_literal_password "$example" || violations=$((violations + $?))
done < <(find . -name ".env.example" -not -path "./.git/*" -not -path "./node_modules/*" -not -path "./docs/*")

if [ $violations -gt 0 ]; then
  echo ""
  echo "::error::共 $violations 個違規 — 規範見 docs/conventions/env-naming.md"
  exit 1
fi
echo ""
echo "✅ 所有 .env.example 通過 syntax / 白名單檢查"
