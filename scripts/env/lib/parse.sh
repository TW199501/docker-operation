#!/usr/bin/env bash
# =============================================================================
# .env.example parser:逐行解析,輸出機器可讀格式
# =============================================================================

# 解析一行 .env.example,輸出 "KEY|VALUE|HAS_EXPR|IS_EMPTY"
# 跳過註解行與空行(輸出空字串)
env_parse_line() {
  local line="$1"
  # 移除前後空白
  line=$(printf '%s' "$line" | sed -E 's/^[[:space:]]+//;s/[[:space:]]+$//')

  # 空行或註解(整行 #)
  if [ -z "$line" ] || [[ "$line" =~ ^# ]]; then
    return
  fi

  # 必須含 = 才是賦值行
  if [[ ! "$line" =~ = ]]; then
    return
  fi

  # 拆 KEY 與 RAW_VALUE
  local key="${line%%=*}"
  local raw_value="${line#*=}"

  # 切掉同行 # 註解(若值以 " 開頭,保護引號內的 #)
  local value="$raw_value"
  if [[ "$raw_value" =~ ^\" ]]; then
    # 含引號:取出第一個完整 "..." 內容
    value=$(printf '%s' "$raw_value" | sed -E 's/^("[^"]*").*$/\1/')
  else
    # 無引號:第一個 # 起切掉
    value=$(printf '%s' "$raw_value" | sed -E 's/[[:space:]]*#.*$//')
  fi
  # 移除末尾空白
  value=$(printf '%s' "$value" | sed -E 's/[[:space:]]+$//')

  # 判斷
  local has_expr=0
  [[ "$value" == *'$('* ]] && has_expr=1

  local is_empty=0
  [ -z "$value" ] && is_empty=1

  printf '%s|%s|%s|%s\n' "$key" "$value" "$has_expr" "$is_empty"
}
