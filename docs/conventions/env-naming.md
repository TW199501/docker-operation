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

> ⚠️ **禁用 `//` C-style 註解** — bash 會把 `//` 後當成值的一部分。

## 3. 命令白名單

`$(...)` 內**只能使用**以下命令(由 `scripts/env/lib/whitelist.sh` 強制):

| 命令 | 用途 | 範例 |
|---|---|---|
| `openssl` | 隨機字串 | `$(openssl rand -base64 32)` |
| `uuidgen` | UUID v4 | `$(uuidgen)` |
| `date` | 日期/時戳 | `$(date +%Y-%m-%d)` |
| `hostname` | 本機主機名 | `$(hostname)` |
| `cat` | 從檔讀(配 `/dev/urandom` 等) | `$(cat /etc/hostname)` |
| `tr` | 字串轉換 | `$(cat /dev/urandom \| tr -dc A-Z0-9 \| head -c 8)` |
| `head` / `tail` | pipe 配合 | 同上 |
| `echo` / `printf` | pipe 配合 | - |

**禁止**:`curl` / `wget` / `bash` / `sh` / `eval` / `python` / `node` / 任何網路命令。

## 4. Bootstrap 用法

```bash
# 對單一 stack 跑(產出該目錄的 .env)
./scripts/env/bootstrap-env.sh DB/POSTGRES

# 預覽不寫檔
./scripts/env/bootstrap-env.sh --dry-run DB/POSTGRES

# 強制覆寫已存在的 .env(會 backup 為 .env.bak.YYYYMMDD-HHMMSS)
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
| `.env.example` 含字面密碼 | `check-env-syntax.sh` | **擋 PR**(heuristic) |
| compose.yml `${VAR}` 不在 `.env.example` | `check-env-coverage.sh` | **警告**(advisory) |

## 6. 範本

完整 `.env.example` 範本見 [`env-example-template.txt`](env-example-template.txt)。
