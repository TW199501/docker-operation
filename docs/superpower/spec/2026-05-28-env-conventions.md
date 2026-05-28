# .env 命名規範 + Bootstrap 工具鏈 Spec — 實作層

> **類型:** Spec(實作層)
> **建立日期:** 2026-05-28
> **對應 Plan:** [`../plan/2026-05-28-env-conventions.md`](../plan/2026-05-28-env-conventions.md)
> **基底分支:** `chore/ci-align-team-template`

---

## 0. 變更總覽

| 類別 | 數量 | 位置 |
|---|---|---|
| 新建檔案 | 8 | `docs/conventions/env-naming.md`、`scripts/env/{bootstrap-env.sh,check-env-syntax.sh,check-env-coverage.sh,README.md}`、`scripts/env/lib/{whitelist.sh,parse.sh}`、`tests/env/test_bootstrap.bats` |
| 修改檔案 | 13 | `CLAUDE.md` + 11 個 `.env.example` + `.github/workflows/docker-ci.yml` |
| 緊急處理 | 1 | `gitea/.env.example:31` 疑似真密碼 |

---

## Task 0 — gitea/.env.example:31 緊急處理

> 對應 Plan: Task 0

### 0.1 確認真假(問 user)

```bash
# 看上下文
sed -n '25,35p' /d/app/docker-operation/gitea/.env.example
```

**問 user 兩個問題:**
1. `'Elf23887711'` 是真實使用過的密碼還是 fake placeholder?
2. 若真,該密碼目前是否仍在用?(生產 DB / gitea 系統等)

### 0.2 處理分支

**Case A:fake** → 改為 `$(openssl rand -base64 24)`,進 Task 6 統一處理。

**Case B:真實但已不用** → 改為 `$(openssl rand -base64 24)`,記錄在 commit message。

**Case C:真實且還在用** → 此時:
1. **立刻** revoke / 改密碼
2. 評估是否 `git filter-repo` rewrite(repo 是否 public?)
3. 改 `.env.example` 為 `$(openssl rand -base64 24)`

```bash
# Case C 範例(視 user 確認後執行)
# 1. 在 gitea / DB 改密碼(out-of-band)
# 2. 改 .env.example
sed -i "s|'Elf23887711'|\$(openssl rand -base64 24)|" gitea/.env.example
# 3. 評估 history rewrite — 屬高風險,需 user 明確同意
```

### 0.3 Commit(Case A 或 B)

```bash
git add gitea/.env.example
git commit -m "fix(security): replace literal password in gitea/.env.example

- Line 31 contained 'Elf23887711' as literal — replaced with $(openssl rand ...)
- (Case [A:fake / B:revoked]) per user confirmation
- 對應 Plan Task 0、Spec §Task 0"
```

---

## Task 1 — `.env` 命名規範文件

> 對應 Plan: Task 1

### 1.1 `docs/conventions/env-naming.md` 內容

````markdown
# .env / .env.example 命名規範

> **規範狀態:** Active(2026-05-28 起)
> **對應工具:** `scripts/env/bootstrap-env.sh`
> **CI 強制:** `check-env-syntax.sh`(語法 / 白名單)、`check-env-coverage.sh`(advisory)

---

## 1. 核心模型

```
.env.example(進 git)──> bootstrap-env.sh ──> .env(不進 git)──> docker-compose
```

- `.env.example` 是**源頭**,**禁止寫真實密碼**
- `.env` 是**衍生產出**,**禁止進 git**(`.gitignore` 已擋)
- `docker-compose` 只讀 `.env`,**不會展開 `$(...)`**;務必先跑 bootstrap

## 2. 語法規則(共 5 條)

### Rule 1 — 字面值

```bash
TZ=Asia/Taipei
POSTGRES_DB=myapp
POSTGRES_USER=postgres
```

### Rule 2 — 自動生成(隨機)

只能使用**白名單命令**(見 §3):

```bash
POSTGRES_PASSWORD=$(openssl rand -base64 32)   # 32 字元 base64
JWT_SECRET=$(openssl rand -hex 64)             # 128 字元 hex
SESSION_SECRET=$(openssl rand -base64 48)
APP_UUID=$(uuidgen)
INSTALL_DATE=$(date +%Y-%m-%d)
HOST_NAME=$(hostname)
```

### Rule 3 — 必填(空值 = 互動 prompt)

```bash
ADMIN_EMAIL=                                   # bootstrap 會詢問
SMTP_HOST=
DOMAIN=
```

### Rule 4 — 含空格 / 特殊字元必須引號

```bash
APP_NAME="My ACME App"
WELCOME_MSG="Hello, world!"
JWT_AUDIENCE="my-api,my-web"
```

> ⚠️ 不引號的話 `bash source` 會把空格後當指令執行而炸。

### Rule 5 — 註解風格

```bash
# === 區塊註解(獨立行)===

POSTGRES_DB=myapp                              # 同行註解(說明用途)
POSTGRES_PASSWORD=$(openssl rand -base64 32)   # 自動生成,32 字元
```

## 3. 命令白名單

`$(...)` 內**只能使用**以下命令(由 `scripts/env/lib/whitelist.sh` 強制):

| 命令 | 用途 | 範例 |
|---|---|---|
| `openssl rand` | 隨機字串 | `$(openssl rand -base64 32)` |
| `uuidgen` | UUID v4 | `$(uuidgen)` |
| `date` | 日期/時戳 | `$(date +%Y-%m-%d)` |
| `hostname` | 本機主機名 | `$(hostname)` |
| `cat` | 從檔讀(配 `/dev/urandom` 等) | `$(cat /etc/hostname)` |
| `tr` | 字串轉換(配 pipe) | `$(cat /dev/urandom \| tr -dc A-Z0-9 \| head -c 8)` |
| `head` `tail` | pipe 配合 | 同上 |

**禁止**:`curl` / `wget` / `bash` / `sh` / `eval` / `python` / `node` / 任何網路命令。

## 4. Bootstrap 用法

```bash
# 對單一 stack 跑(產出該目錄的 .env)
./scripts/env/bootstrap-env.sh DB/POSTGRES

# 預覽不寫檔
./scripts/env/bootstrap-env.sh --dry-run DB/POSTGRES

# 強制覆寫已存在的 .env
./scripts/env/bootstrap-env.sh --force DB/POSTGRES

# 非互動模式(空值會失敗而非 prompt,CI 用)
./scripts/env/bootstrap-env.sh --non-interactive DB/POSTGRES

# 對全 repo 所有 stack 跑(慎用)
./scripts/env/bootstrap-env.sh --all
```

## 5. 違規處理(由 CI 執行)

| 違規 | CI 步驟 | 行為 |
|---|---|---|
| `.env.example` 含白名單外命令 | `check-env-syntax.sh` | **擋 PR**(exit 1) |
| `.env.example` 含字面密碼 | `check-env-syntax.sh` | **擋 PR**(heuristic:`PASSWORD=非空非$()非引號 8+ 字元`) |
| compose.yml `${VAR}` 不在 `.env.example` | `check-env-coverage.sh` | **警告**(advisory) |

## 6. 範本

完整 `.env.example` 範本見 [`docs/conventions/env-example-template.txt`](env-example-template.txt)(本 plan Task 1.2 產出)。
````

### 1.2 範本檔 `docs/conventions/env-example-template.txt`

```bash
# =============================================================================
# .env.example template
# 對應 stack:<stack-name>
# 規範:docs/conventions/env-naming.md
# 用法:./scripts/env/bootstrap-env.sh <this-directory>
# =============================================================================

# === 基本設定 ===
TZ=Asia/Taipei
APP_NAME="My Stack"

# === Database ===
POSTGRES_DB=myapp                              # DB 名稱
POSTGRES_USER=postgres                         # DB 使用者
POSTGRES_PASSWORD=$(openssl rand -base64 32)   # 自動生成

# === Admin ===
ADMIN_EMAIL=                                   # 必填(bootstrap 詢問)
ADMIN_PASSWORD=$(openssl rand -base64 24)
JWT_SECRET=$(openssl rand -hex 64)

# === Networking ===
DOMAIN=                                        # 必填
HOST_NAME=$(hostname)
```

### 1.3 CLAUDE.md 段落(於 `## Compose 檔命名規範` 之後插入)

```markdown
## .env 命名規範

**完整規範:** [`docs/conventions/env-naming.md`](docs/conventions/env-naming.md)

**核心模型:** `.env.example`(進 git)→ `scripts/env/bootstrap-env.sh` → `.env`(不進 git)→ docker-compose

**5 條語法:**
- 字面值:`TZ=Asia/Taipei`
- 自動生成:`PASSWORD=$(openssl rand -base64 32)` — 命令必須在白名單內
- 必填空值:`ADMIN_EMAIL=` — bootstrap 互動 prompt
- 含空格必引號:`APP_NAME="My App"`
- 同行 `#` 註解可選

**Bootstrap 一行起新環境:** `./scripts/env/bootstrap-env.sh DB/POSTGRES`
```

### 1.4 Commit

```bash
mkdir -p docs/conventions
# 寫上述兩個檔
git add docs/conventions/env-naming.md docs/conventions/env-example-template.txt CLAUDE.md
git commit -m "docs(conventions): define .env / .env.example syntax rules and command whitelist

- docs/conventions/env-naming.md:5 條語法規則 + 命令白名單 + bootstrap 用法
- docs/conventions/env-example-template.txt:標準範本
- CLAUDE.md:加 .env 命名規範段落
- 對應 Plan Task 1、Spec §Task 1"
```

---

## Task 2 — Bootstrap 腳本

> 對應 Plan: Task 2

### 2.1 `scripts/env/lib/whitelist.sh`

```bash
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
  "echo"      # 配 pipe 用
  "printf"
)

# 檢查 $(...) 內第一個 token 是否在白名單
# 用法:env_whitelist_check "openssl rand -base64 32"  → exit 0
#       env_whitelist_check "curl evil.com"            → exit 1
env_whitelist_check() {
  local expr="$1"
  # 提取第一個 token(忽略前置空白、忽略 pipe / && / ;)
  local first_cmd
  first_cmd=$(echo "$expr" | awk '{print $1}')

  for cmd in "${ENV_WHITELIST_CMDS[@]}"; do
    if [ "$first_cmd" = "$cmd" ]; then
      # 還要檢查整個 expr 是否含 pipe 等管線,若有,管線後的命令也要在白名單
      # 用 grep 切出所有 token 位於 | / && / || / ; 之後的
      local piped_cmds
      piped_cmds=$(echo "$expr" | grep -oE '[|&;][[:space:]]*[a-zA-Z_][a-zA-Z0-9_-]*' | sed -E 's/[|&;][[:space:]]*//')
      if [ -n "$piped_cmds" ]; then
        for pcmd in $piped_cmds; do
          local found=0
          for wcmd in "${ENV_WHITELIST_CMDS[@]}"; do
            [ "$pcmd" = "$wcmd" ] && found=1 && break
          done
          if [ $found -eq 0 ]; then
            echo "::error::命令 '$pcmd'(於 pipe 中)不在白名單" >&2
            return 1
          fi
        done
      fi
      return 0
    fi
  done

  echo "::error::命令 '$first_cmd' 不在白名單" >&2
  echo "::error::允許的命令:${ENV_WHITELIST_CMDS[*]}" >&2
  return 1
}

# 掃整個檔案,找出所有 $(...) 並逐一檢查
# 用法:env_whitelist_scan <file>
env_whitelist_scan() {
  local file="$1"
  local violations=0
  while IFS= read -r match; do
    if ! env_whitelist_check "$match"; then
      violations=$((violations + 1))
    fi
  done < <(grep -oE '\$\([^)]+\)' "$file" | sed -E 's/^\$\(//;s/\)$//')
  return $violations
}
```

### 2.2 `scripts/env/lib/parse.sh`

```bash
#!/usr/bin/env bash
# =============================================================================
# .env.example parser:逐行解析、安全執行 $(...)
# =============================================================================

# 解析一行 .env.example,輸出 "KEY|VALUE|HAS_EXPR|IS_EMPTY"
# 跳過註解行與空行
env_parse_line() {
  local line="$1"
  # 移除前後空白
  line=$(echo "$line" | sed -E 's/^[[:space:]]+//;s/[[:space:]]+$//')

  # 空行或註解
  if [ -z "$line" ] || [[ "$line" =~ ^# ]]; then
    echo ""
    return
  fi

  # 拆 KEY 與 RAW_VALUE(VALUE 含同行 # 註解)
  local key="${line%%=*}"
  local raw_value="${line#*=}"

  # 切掉同行 # 註解(只切第一個未被引號保護的 #)
  local value="$raw_value"
  # 簡化策略:若 raw_value 以 " 開頭,找第二個 " 後再切 #
  if [[ "$raw_value" =~ ^\".*\"[[:space:]]*#? ]]; then
    value=$(echo "$raw_value" | sed -E 's/^("[^"]*").*$/\1/')
  else
    value=$(echo "$raw_value" | sed -E 's/[[:space:]]*#.*$//')
  fi
  # 移除末尾空白
  value=$(echo "$value" | sed -E 's/[[:space:]]+$//')

  # 判斷是否含 $(...)
  local has_expr=0
  [[ "$value" =~ \$\(.+\) ]] && has_expr=1

  # 判斷是否空值
  local is_empty=0
  [ -z "$value" ] && is_empty=1

  echo "${key}|${value}|${has_expr}|${is_empty}"
}
```

### 2.3 `scripts/env/bootstrap-env.sh`

```bash
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

# 顏色(stderr 不上色,給 CI 看的乾淨)
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
      printf "  ${C_CYAN}? %s = ${C_RESET}" "$key" >&2
      read -r value < /dev/tty
    fi

    # $(...) 展開:先 source 一次(白名單已過,安全)
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
  done < <(find . -name ".env.example" -not -path "./.git/*" -not -path "./node_modules/*")
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
```

### 2.4 `scripts/env/README.md`

```markdown
# scripts/env/

`.env.example` → `.env` bootstrap 工具鏈。

## 用法

見 [`docs/conventions/env-naming.md`](../../docs/conventions/env-naming.md) §4。

## 檔案

- `bootstrap-env.sh` — 主入口
- `check-env-syntax.sh` — CI 用,擋字面密碼與白名單外命令
- `check-env-coverage.sh` — CI 用(advisory),掃 compose.yml `${VAR}` 是否在 example 有定義
- `lib/whitelist.sh` — 命令白名單實作
- `lib/parse.sh` — `.env.example` parser
```

### 2.5 Commit

```bash
mkdir -p scripts/env/lib
# 寫上述 4 個檔
chmod +x scripts/env/bootstrap-env.sh
git add scripts/env/
git commit -m "feat(env): add bootstrap-env.sh with whitelist and prompt support

- bootstrap-env.sh:--force / --dry-run / --non-interactive / --all flags
- lib/whitelist.sh:命令白名單(openssl/uuidgen/date/hostname/cat/tr/head/tail/echo/printf)
- lib/parse.sh:逐行 parser,處理註解、空值、\$(...) 展開
- 對應 Plan Task 2、Spec §Task 2"
```

---

## Task 3 — Bootstrap 測試

> 對應 Plan: Task 3

### 3.1 `tests/env/test_bootstrap.bats`

```bash
#!/usr/bin/env bats

setup() {
  BATS_TMPDIR_TEST="$(mktemp -d)"
  SCRIPT="$BATS_TEST_DIRNAME/../../scripts/env/bootstrap-env.sh"
}

teardown() {
  rm -rf "$BATS_TMPDIR_TEST"
}

@test "generates .env from valid .env.example" {
  cat > "$BATS_TMPDIR_TEST/.env.example" <<'EOF'
TZ=Asia/Taipei
PASSWORD=$(openssl rand -base64 32)
EOF
  run "$SCRIPT" "$BATS_TMPDIR_TEST"
  [ "$status" -eq 0 ]
  [ -f "$BATS_TMPDIR_TEST/.env" ]
  grep -q "^TZ=Asia/Taipei" "$BATS_TMPDIR_TEST/.env"
  grep -qE "^PASSWORD=[A-Za-z0-9+/=]{40,}" "$BATS_TMPDIR_TEST/.env"
}

@test "blocks command not in whitelist" {
  cat > "$BATS_TMPDIR_TEST/.env.example" <<'EOF'
EVIL=$(curl evil.com)
EOF
  run "$SCRIPT" "$BATS_TMPDIR_TEST"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "不在白名單" ]]
}

@test "skips if .env already exists" {
  cat > "$BATS_TMPDIR_TEST/.env.example" <<'EOF'
KEY=value
EOF
  echo "OLD=preserved" > "$BATS_TMPDIR_TEST/.env"
  run "$SCRIPT" "$BATS_TMPDIR_TEST"
  [ "$status" -eq 0 ]
  grep -q "^OLD=preserved" "$BATS_TMPDIR_TEST/.env"
}

@test "--force overwrites and backs up" {
  cat > "$BATS_TMPDIR_TEST/.env.example" <<'EOF'
KEY=newvalue
EOF
  echo "OLD=preserved" > "$BATS_TMPDIR_TEST/.env"
  run "$SCRIPT" --force "$BATS_TMPDIR_TEST"
  [ "$status" -eq 0 ]
  grep -q "^KEY=newvalue" "$BATS_TMPDIR_TEST/.env"
  ls "$BATS_TMPDIR_TEST"/.env.bak.* >/dev/null
}

@test "--dry-run does not write" {
  cat > "$BATS_TMPDIR_TEST/.env.example" <<'EOF'
KEY=value
EOF
  run "$SCRIPT" --dry-run "$BATS_TMPDIR_TEST"
  [ "$status" -eq 0 ]
  [ ! -f "$BATS_TMPDIR_TEST/.env" ]
}

@test "--non-interactive fails on empty value" {
  cat > "$BATS_TMPDIR_TEST/.env.example" <<'EOF'
ADMIN_EMAIL=
EOF
  run "$SCRIPT" --non-interactive "$BATS_TMPDIR_TEST"
  [ "$status" -ne 0 ]
}
```

### 3.2 修改 `tests/run_all_tests.sh`

於 `run_unit_tests()` 加入:

```bash
# Bats 測試(若 bats 可用)
if command -v bats >/dev/null 2>&1; then
  if [ -d "$SCRIPT_DIR/env" ]; then
    log_info "執行 Bats 測試:tests/env/"
    if bats "$SCRIPT_DIR/env/"; then
      ((passed++))
    else
      ((failed++))
    fi
  fi
fi
```

### 3.3 Commit

```bash
mkdir -p tests/env
# 寫測試檔
git add tests/env/test_bootstrap.bats tests/run_all_tests.sh
git commit -m "test(env): add bats tests for bootstrap-env.sh

- 6 test cases:正常路徑 / 白名單擋 / skip / force / dry-run / non-interactive
- run_all_tests.sh 加 bats hook
- 對應 Plan Task 3、Spec §Task 3"
```

---

## Task 4 — CI:syntax 白名單檢查

> 對應 Plan: Task 4

### 4.1 `scripts/env/check-env-syntax.sh`

```bash
#!/usr/bin/env bash
# CI 用:掃全 repo .env.example,檢查 $(...) 在白名單內、字面密碼擋下
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/whitelist.sh
source "$SCRIPT_DIR/lib/whitelist.sh"

violations=0

while IFS= read -r example; do
  echo "=== $example ==="

  # 1. 白名單
  if ! env_whitelist_scan "$example"; then
    violations=$((violations + 1))
  fi

  # 2. 字面密碼 heuristic
  # 模式:PASSWORD-like key = 非空非 $() 非引號 8+ alphanum 字元
  while IFS= read -r line; do
    if [[ "$line" =~ ^[[:space:]]*([A-Z_]*(PASSWORD|PASSWD|SECRET|TOKEN|KEY)[A-Z_]*)=([^[:space:]#]+) ]]; then
      local_value="${BASH_REMATCH[3]}"
      # 排除 $(...) / " / 空值 / 顯然佔位
      if [[ ! "$local_value" =~ ^\$\( ]] && \
         [[ ! "$local_value" =~ ^\" ]] && \
         [[ "$local_value" =~ ^[A-Za-z0-9!@#$%^*_-]{8,}$ ]] && \
         [[ ! "$local_value" =~ ^your_ ]] && \
         [[ ! "$local_value" =~ _here$ ]] && \
         [[ "$local_value" != "${BASH_REMATCH[1]}" ]]; then
        echo "::error file=$example::疑似硬編碼密碼:${BASH_REMATCH[1]}=$local_value"
        violations=$((violations + 1))
      fi
    fi
  done < "$example"
done < <(find . -name ".env.example" -not -path "./.git/*" -not -path "./node_modules/*")

if [ $violations -gt 0 ]; then
  echo "::error::$violations 個違規"
  exit 1
fi
echo "✅ 所有 .env.example 通過 syntax / 白名單檢查"
```

### 4.2 docker-ci.yml basics job 加 step

於 Block .env and secret files step 之後加:

```yaml
      - name: Check .env.example syntax and whitelist
        run: |
          chmod +x scripts/env/check-env-syntax.sh
          bash scripts/env/check-env-syntax.sh
```

### 4.3 Commit

```bash
chmod +x scripts/env/check-env-syntax.sh
git add scripts/env/check-env-syntax.sh .github/workflows/docker-ci.yml
git commit -m "ci: enforce .env.example syntax and command whitelist

- check-env-syntax.sh:掃全 repo .env.example
  * \$(...) 命令必須在 whitelist.sh
  * heuristic 擋字面密碼(PASSWORD/SECRET/TOKEN/KEY 後接 alphanum 8+ 且非 \$())
- docker-ci.yml basics job 加 step,強制執行
- 對應 Plan Task 4、Spec §Task 4"
```

---

## Task 5 — CI:example ↔ compose 覆蓋率(advisory)

> 對應 Plan: Task 5

### 5.1 `scripts/env/check-env-coverage.sh`

```bash
#!/usr/bin/env bash
# CI 用(advisory):對每個有 compose.yml 的目錄,確認 ${VAR} 都在 .env.example 有定義
set -euo pipefail

violations=0

# 找所有含 docker-compose*.yml 的目錄
while IFS= read -r compose; do
  dir=$(dirname "$compose")
  example="$dir/.env.example"

  # 從 compose 抓所有 ${VAR}(排除 ${VAR:-default} 之類有 fallback 的)
  used_vars=$(grep -oE '\$\{[A-Z_][A-Z0-9_]*\}' "$compose" | sort -u | sed -E 's/^\$\{//;s/\}$//')

  [ -z "$used_vars" ] && continue

  if [ ! -f "$example" ]; then
    # advisory:沒 example 但 compose 有用 ${VAR}
    echo "::warning file=$compose::使用 \${VAR} 但本目錄無 .env.example"
    violations=$((violations + 1))
    continue
  fi

  # 對每個 var 確認 .env.example 內有定義
  for var in $used_vars; do
    if ! grep -qE "^${var}=" "$example"; then
      echo "::warning file=$example::compose.yml 用了 \${${var}} 但本檔未定義"
      violations=$((violations + 1))
    fi
  done
done < <(find . -name "docker-compose*.yml" -not -path "./.git/*" -not -path "./docs/*")

if [ $violations -gt 0 ]; then
  echo "::warning::共 $violations 個覆蓋率缺口(advisory,不擋 PR)"
fi
echo "✅ 覆蓋率掃描完成"
```

### 5.2 docker-ci.yml basics job 加 step(advisory)

```yaml
      - name: Check .env.example covers compose variables (advisory)
        continue-on-error: true
        run: |
          chmod +x scripts/env/check-env-coverage.sh
          bash scripts/env/check-env-coverage.sh
```

### 5.3 Commit

```bash
chmod +x scripts/env/check-env-coverage.sh
git add scripts/env/check-env-coverage.sh .github/workflows/docker-ci.yml
git commit -m "ci: advisory check for .env.example ↔ compose.yml variable coverage

- check-env-coverage.sh:對每個 compose.yml,確認 \${VAR} 都在同目錄 .env.example
  * advisory(continue-on-error: true,僅 warn)
  * 待 Task 6 改完 11 個 example、確認無 false positive 後轉強制
- 對應 Plan Task 5、Spec §Task 5"
```

---

## Task 6 — 改寫 11 個既有 `.env.example`

> 對應 Plan: Task 6

### 6.1 對照表(原 → 新)

每個 example 處理原則:
- 密碼類 → `$(openssl rand -base64 32)` 或 `$(openssl rand -base64 24)`
- token 類 → `$(openssl rand -hex 32)`
- email / domain / endpoint 等使用者特定 → 空值(bootstrap prompt)
- 字面值(DB 名 / port / encoding)→ 保持原值或合理預設

### 6.2 逐檔修改

(內容範例見 11 個檔的個別處理,實作時依規範統一)

主要變動類型:
- `DB/POSTGRES/.env.example`:`POSTGRES_PASSWORD=your_secure_password_here` → `$(openssl rand -base64 32)`
- `DB/SQLServer/oneSQLServer/.env.example`:`MSSQL_SA_PASSWORD=YourStrong!Password123` → `$(openssl rand -base64 24)`(MSSQL 密碼有複雜度要求,需另加 prefix 或 suffix 確保符合)
- `DB/redis/.env.example`:`REDIS_PASSWORD=REDIS_PASSWORD` → `$(openssl rand -base64 32)`
- `openwebui/.env.example`:全部變數從重複名改成 `$(openssl rand ...)` 或空值
- `cloudflare/.env.example`:`CLOUDFLARE_TUNNEL_TOKEN=your_actual_tunnel_token_here` → 空值(必填,使用者自取)
- 其他依規範對齊

### 6.3 Commit(一個檔一個 commit,共 11 個)

```bash
# 範例 — DB/POSTGRES
git add DB/POSTGRES/.env.example
git commit -m "refactor(env): align DB/POSTGRES/.env.example to convention"
# ... 11 個
```

或合併為一個 commit:

```bash
git add */.env.example DB/**/.env.example
git commit -m "refactor(env): align all 11 .env.example files to syntax convention

- 密碼類改為 \$(openssl rand -base64 N)
- token 改為 \$(openssl rand -hex N)
- 使用者特定值改為空值(bootstrap prompt)
- 統一加區塊註解標示分組
- 對應 Plan Task 6、Spec §Task 6"
```

**取捨**:合併 commit review 較快,但若某檔有 case-specific decision,拆獨立 commit 較好追溯。本 task 採合併 commit。

---

## Task 7 — 全域驗證 + 推送

> 對應 Plan: Task 7

### 7.1 對 11 個 stack 跑 dry-run

```bash
cd /d/app/docker-operation
for d in $(find . -name ".env.example" -not -path "./.git/*" | xargs -I{} dirname {}); do
  echo "=== $d ==="
  ./scripts/env/bootstrap-env.sh --dry-run --non-interactive "$d" 2>&1 | head -10
done
```

### 7.2 跑 Bats 測試

```bash
bats tests/env/
```

### 7.3 跑 CI script 本機驗證

```bash
bash scripts/env/check-env-syntax.sh
bash scripts/env/check-env-coverage.sh
```

### 7.4 全域 commit log + 推送

```bash
git log --oneline 826f42c..HEAD
git push -u origin chore/env-conventions
```
