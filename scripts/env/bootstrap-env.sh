#!/usr/bin/env bash
# =============================================================================
# .env bootstrap — 把 .env.example 展開成 .env
# 規範:docs/conventions/env-naming.md
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/whitelist.sh
source "$SCRIPT_DIR/lib/whitelist.sh"
# shellcheck source=lib/parse.sh
source "$SCRIPT_DIR/lib/parse.sh"

# 顏色(非 TTY 不上色,給 CI 看的乾淨)
if [ -t 1 ]; then
  C_RED='\033[31m'; C_GREEN='\033[32m'; C_YELLOW='\033[33m'; C_CYAN='\033[36m'; C_RESET='\033[0m'
else
  C_RED=''; C_GREEN=''; C_YELLOW=''; C_CYAN=''; C_RESET=''
fi

# Flags
FORCE=0
DRY_RUN=0
NON_INTERACTIVE=0
ALL=0
TARGETS=()

usage() {
  cat <<EOF
Usage: $0 [flags] <stack-dir>...
       $0 [flags] --all

Flags:
  --force            覆寫已存在的 .env(會 backup 為 .env.bak.YYYYMMDD-HHMMSS)
  --dry-run          只印結果,不寫檔
  --non-interactive  空值不 prompt,直接失敗(CI 用)
  --all              對全 repo 所有含 .env.example 的目錄跑
  -h, --help         顯示本說明
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --force) FORCE=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --non-interactive) NON_INTERACTIVE=1; shift ;;
    --all) ALL=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --*) echo "Unknown flag: $1" >&2; usage >&2; exit 1 ;;
    *) TARGETS+=("$1"); shift ;;
  esac
done

# 必備工具檢查
require_tools() {
  local missing=()
  for t in openssl awk grep sed; do
    command -v "$t" >/dev/null || missing+=("$t")
  done
  if [ ${#missing[@]} -gt 0 ]; then
    echo -e "${C_RED}缺少必備工具:${missing[*]}${C_RESET}" >&2
    return 1
  fi
}
require_tools || exit 1

# 處理單一目錄
process_stack() {
  local stack_dir="$1"
  local example="$stack_dir/.env.example"
  local target="$stack_dir/.env"

  echo -e "${C_CYAN}== $stack_dir ==${C_RESET}"

  if [ ! -f "$example" ]; then
    echo -e "  ${C_YELLOW}skip:沒有 .env.example${C_RESET}"
    return 0
  fi

  # 1. 白名單檢查
  if ! env_whitelist_scan "$example"; then
    echo -e "  ${C_RED}fail:.env.example 含白名單外命令${C_RESET}" >&2
    return 1
  fi

  # 2. 已存在 .env 處理
  if [ -f "$target" ] && [ $FORCE -eq 0 ]; then
    echo -e "  ${C_YELLOW}skip:.env 已存在(用 --force 覆寫)${C_RESET}"
    return 0
  fi

  if [ -f "$target" ] && [ $FORCE -eq 1 ] && [ $DRY_RUN -eq 0 ]; then
    local backup
    backup="$target.bak.$(date +%Y%m%d-%H%M%S)"
    cp "$target" "$backup"
    echo -e "  ${C_YELLOW}backup:現有 .env → $(basename "$backup")${C_RESET}"
  fi

  # 3. 解析每行
  local output=""
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    local parsed
    parsed=$(env_parse_line "$line")

    if [ -z "$parsed" ]; then
      # 註解或空行,原樣輸出
      output+="$line"$'\n'
      continue
    fi

    local key value has_expr is_empty
    IFS='|' read -r key value has_expr is_empty <<< "$parsed"

    # 空值:互動 prompt 或失敗
    if [ "$is_empty" = "1" ]; then
      if [ $NON_INTERACTIVE -eq 1 ]; then
        echo -e "  ${C_RED}fail:$key 為空(non-interactive 模式)${C_RESET}" >&2
        return 1
      fi
      printf "  ? %s = " "$key" >&2
      read -r value < /dev/tty
    fi

    # $(...) 展開:eval echo 安全執行(白名單已過)
    if [ "$has_expr" = "1" ]; then
      value=$(eval "echo $value")
    fi

    output+="${key}=${value}"$'\n'
  done < "$example"

  # 4. 輸出
  if [ $DRY_RUN -eq 1 ]; then
    echo -e "  ${C_GREEN}dry-run output:${C_RESET}"
    echo "$output" | sed 's/^/    /'
  else
    echo "$output" > "$target"
    echo -e "  ${C_GREEN}ok:.env 已產出${C_RESET}"
  fi
}

# 取得目標
if [ $ALL -eq 1 ]; then
  while IFS= read -r f; do
    TARGETS+=("$(dirname "$f")")
  done < <(find . -name ".env.example" -not -path "./.git/*" -not -path "./node_modules/*" -not -path "./docs/*")
fi

if [ ${#TARGETS[@]} -eq 0 ]; then
  echo "未指定目標(用 <stack-dir> 或 --all)" >&2
  usage >&2
  exit 1
fi

# 逐一處理
overall_result=0
for t in "${TARGETS[@]}"; do
  process_stack "$t" || overall_result=1
done

exit $overall_result
