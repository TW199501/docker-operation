#!/usr/bin/env bash
# =============================================================================
# 命令白名單 — .env.example 中 $(...) 只能使用這裡列的命令
# 規範:docs/conventions/env-naming.md §3
# =============================================================================

# 允許的命令(基本款,可隨團隊規範擴充)
ENV_WHITELIST_CMDS=(
  "openssl"
  "uuidgen"
  "date"
  "hostname"
  "cat"
  "tr"
  "head"
  "tail"
  "echo"
  "printf"
)

# 檢查單一命令 token 是否在白名單
_env_whitelist_contains() {
  local needle="$1"
  for cmd in "${ENV_WHITELIST_CMDS[@]}"; do
    [ "$needle" = "$cmd" ] && return 0
  done
  return 1
}

# 檢查 $(...) 內運算式(可含 pipe / && / ||)
# 用法:env_whitelist_check "openssl rand -base64 32"  → exit 0
#       env_whitelist_check "curl evil.com"            → exit 1
#       env_whitelist_check "cat /dev/urandom | tr -dc A-Z | head -c 8" → exit 0
env_whitelist_check() {
  local expr="$1"
  # 切出所有「位於開頭或 | && || ; 之後的第一個 token」
  # 用 awk 處理會比較乾淨
  local cmds
  cmds=$(echo "$expr" | awk '
    BEGIN { RS="[|;]|&&|\\|\\|" }
    {
      gsub(/^[[:space:]]+/, "")
      n = split($0, parts, /[[:space:]]+/)
      if (n > 0 && parts[1] != "") print parts[1]
    }
  ')

  while IFS= read -r cmd; do
    [ -z "$cmd" ] && continue
    if ! _env_whitelist_contains "$cmd"; then
      echo "::error::命令 '$cmd' 不在白名單" >&2
      echo "::error::允許的命令:${ENV_WHITELIST_CMDS[*]}" >&2
      return 1
    fi
  done <<< "$cmds"
  return 0
}

# 掃整個檔案,找出所有 $(...) 並逐一檢查
# 用法:env_whitelist_scan <file>
# 回傳 0 = 全通過,>0 = 違規數量
env_whitelist_scan() {
  local file="$1"
  local violations=0
  local match
  while IFS= read -r match; do
    [ -z "$match" ] && continue
    if ! env_whitelist_check "$match"; then
      violations=$((violations + 1))
    fi
  done < <(grep -oE '\$\([^)]+\)' "$file" 2>/dev/null | sed -E 's/^\$\(//;s/\)$//')
  return $violations
}
