# CI/CD 對齊團隊規範 Spec — 實作細節

> **類型:** Spec(實作層)
> **建立日期:** 2026-05-28
> **對應 Plan:** [`../plan/2026-05-28-cicd-team-conventions.md`](../plan/2026-05-28-cicd-team-conventions.md)
> **狀態:** Draft

---

## 0. 變更總覽

| 類別 | 數量 | 位置 |
| --- | --- | --- |
| 新建檔案 | 11 | `.gitattributes` / `.github/CODEOWNERS` / `.github/scripts/check-line-endings.mjs` / `.github/labeler.yml` / `.github/PULL_REQUEST_TEMPLATE.md` / `.github/ISSUE_TEMPLATE/{bug_report,feature_request,config}.yml` / `.github/workflows/pr-labeler.yml` / `docs/conventions/compose-naming.md` |
| 修改檔案 | 7 | `.gitignore` / `.dockerignore` / `CLAUDE.md` / `.github/dependabot.yml` / `.github/workflows/{docker-ci,docker-publish,script-test,security-scan,proxmox-k8s-ci}.yml` |
| 重新命名 | 1 | `gitea/.env.exampke` → `gitea/.env.example` |
| 一次性 git 操作 | 2 | `git add --renormalize .`(行尾)+ 清理 22 個 stale `D` 變動 |

---

## Task 0 對應實作 — git 髒狀態清理

> 對應 Plan: Task 0「清理 worktree 既有未提交變動」

### 0.1 盤點現況(已執行,2026-05-28 11:50)

```
D 22 個檔: .codebuddy/sandbox/sandbox.json / .kilocode/mcp.json / .mcp/mcp-config.json
          .windsurf/rules/ai-commitment-statement.md
          docs/HAPPY-AI-TODO-TREE.md / docs/STOP-HAPPY-AI.md
          集運數據集/*.md (13 個檔)

M 3 個檔: DB/SQLServer/oneSQLServer/.env.example
         DB/SQLServer/oneSQLServer/docker-compose.yml
         certbot/bootstrap-certificates.sh

?? 4 項:  123.md / CLAUDE.md / DB/sql2022/ / docs/superpower/
```

### 0.2 處理策略(分類)

| 類別 | 處置 | 理由 |
|---|---|---|
| **保留進新分支基線** | `CLAUDE.md`、`docs/superpower/` | 本 session 規範資產,計畫執行必須讀得到 |
| **保留進 main 之後再處理** | `DB/sql2022/`、`DB/SQLServer/oneSQLServer/*.{env.example,docker-compose.yml}`、`certbot/bootstrap-certificates.sh` | user 先前未完成工作,跟本計畫無關,不該被 stash 也不該帶進 ci 分支 |
| **丟棄(stash)** | `123.md` | 看似 scratch 檔,1 byte 內容,先 stash 觀察 |
| **接受刪除(進新分支)** | `.codebuddy/sandbox/sandbox.json`、`.windsurf/rules/ai-commitment-statement.md`、`.mcp/mcp-config.json`、`.kilocode/mcp.json`、`docs/HAPPY-AI-TODO-TREE.md`、`docs/STOP-HAPPY-AI.md`、`集運數據集/` | 多個 AI 工具殘留 + 業務無關「集運數據集」,user 已從 worktree 刪除,計畫順手收尾 |

### 0.3 實作指令

```bash
cd /d/app/docker-operation

# (1) 先建分支(從當前 main HEAD,worktree 變動會跟著過去)
git switch -c chore/ci-align-team-template

# (2) 把「保留進 main 之後再處理」那組 stash 起來
git stash push -m "wip: SQLServer + certbot + sql2022 (跟 CI/CD 對齊計畫無關,暫存)" \
  -- DB/SQLServer/oneSQLServer/.env.example \
     DB/SQLServer/oneSQLServer/docker-compose.yml \
     certbot/bootstrap-certificates.sh \
     DB/sql2022/

# (3) 把 123.md 也 stash(scratch)
git stash push -m "wip: 123.md scratch" -- 123.md

# (4) 把「接受刪除」的 D 類提交(獨立 commit,理由清楚)
git add -u .codebuddy/ .kilocode/ .mcp/ .windsurf/ docs/HAPPY-AI-TODO-TREE.md docs/STOP-HAPPY-AI.md "集運數據集/"
git commit -m "chore: remove stale AI-tool residue and unrelated dataset directory

- .codebuddy/.kilocode/.mcp/.windsurf:多個 AI 工具殘留設定
- docs/HAPPY-AI-TODO-TREE.md / STOP-HAPPY-AI.md:過時草稿
- 集運數據集/:業務無關目錄"

# (5) 把本 session 規範資產進 commit
git add CLAUDE.md docs/superpower/
git commit -m "docs: add CLAUDE.md and docs/superpower/ (plan + spec + memory baseline)"
```

### 0.4 驗證

```bash
git status            # 應僅剩(無輸出 = clean)
git stash list        # 應看到 2 筆 stash(wip)
git log --oneline -3  # 應看到上面 (4)(5) 兩個 commit
```

---

## Task 1 對應實作 — `.gitattributes` + 行尾正規化

> 對應 Plan: Task 1

### 1.1 建立 `.gitattributes`

```gitattributes
# =============================================================================
# 行尾規範 — 對齊團隊範本(E:\source\team-project-template\.gitattributes)
#
# 原則:
#   1. 全域 LF(包含 Windows 開發者本機 checkout 時也轉成 LF)
#   2. 只有 Windows 專屬批次檔(.bat / .cmd / .ps1)強制 CRLF
#   3. 此檔的規範由 .github/scripts/check-line-endings.mjs 在 CI 強制
# =============================================================================

# 預設:所有 text 檔案以 LF 為行尾
* text=auto eol=lf

# 強制 LF (跨平台原始碼)
*.sh         text eol=lf
*.bash       text eol=lf
*.mjs        text eol=lf
*.js         text eol=lf
*.ts         text eol=lf
*.json       text eol=lf
*.yml        text eol=lf
*.yaml       text eol=lf
*.md         text eol=lf
*.conf       text eol=lf
*.ini        text eol=lf
*.env*       text eol=lf
*.example    text eol=lf
Dockerfile*  text eol=lf

# Windows 專屬批次檔強制 CRLF
*.bat        text eol=crlf
*.cmd        text eol=crlf
*.ps1        text eol=crlf

# 二進位:不轉換、不 diff
*.png        binary
*.jpg        binary
*.jpeg       binary
*.gif        binary
*.ico        binary
*.pdf        binary
*.zip        binary
*.tar.gz     binary
*.gz         binary
```

### 1.2 Dry-run 看 renormalize 影響

```bash
cd /d/app/docker-operation
git ls-files --eol | grep -v 'i/lf' | head -50
# 若量很大(>200 行)→ 暫停回報 user
# 若量在可接受範圍 → 繼續執行
```

### 1.3 正規化既有檔案

```bash
git add --renormalize .
git status
# 確認 bump-version.bat 仍是 CRLF
file Dockerfile/bump-version.bat   # 期待:CRLF line terminators
```

### 1.4 Commit

```bash
git add .gitattributes
git add -A   # 接受 renormalize 的結果
git commit -m "chore: add .gitattributes and normalize line endings"
```

---

## Task 2 對應實作 — line-ending CI 腳本

> 對應 Plan: Task 2

### 2.1 複製並微調

```bash
mkdir -p /d/app/docker-operation/.github/scripts
cp /e/source/team-project-template/.github/scripts/check-line-endings.mjs \
   /d/app/docker-operation/.github/scripts/check-line-endings.mjs
chmod +x /d/app/docker-operation/.github/scripts/check-line-endings.mjs
```

### 2.2 微調白名單

開啟 `.github/scripts/check-line-endings.mjs`,於:
- `LF_EXTS` 加入:`'.conf'`, `'.ini'`, `'.env'`
- `LF_FILENAMES` 加入:`'Dockerfile'`(無副檔名)

### 2.3 本機驗證 + commit

```bash
node .github/scripts/check-line-endings.mjs
# 期待:✅ 換行符檢查通過...

git add .github/scripts/check-line-endings.mjs
git commit -m "ci: add line-ending checker (team convention)"
```

---

## Task 3 對應實作 — 重寫 `docker-ci.yml`

> 對應 Plan: Task 3

### 3.1 在 `on:` 後、`jobs:` 前插入

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

permissions:
  contents: read
  pull-requests: read
```

### 3.2 全檔 `actions/checkout@v6` → `@v4`

```bash
sed -i 's|actions/checkout@v6|actions/checkout@v4|g' .github/workflows/docker-ci.yml
grep -n actions/checkout .github/workflows/docker-ci.yml   # 應全為 @v4
```

### 3.3 新增 `basics` job(放在現有 jobs 之前)

```yaml
  basics:
    name: Basics (commit / file check)
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Check commit messages (Conventional Commits)
        if: github.event_name == 'pull_request' && github.base_ref == 'main'
        uses: webiny/action-conventional-commits@v1.3.0

      - name: Setup Node.js (for check scripts)
        uses: actions/setup-node@v6
        with:
          node-version: 20

      - name: Check line endings (LF enforcement)
        run: node .github/scripts/check-line-endings.mjs

      - name: Check for large files (> 5MB)
        run: |
          LARGE_FILES=$(find . -type f -size +5M -not -path "./.git/*" || true)
          if [ -n "$LARGE_FILES" ]; then
            echo "發現大檔案(>5MB),請考慮使用 Git LFS:"
            echo "$LARGE_FILES"
            exit 1
          fi
```

### 3.4 移除 `security-scan` 與 `shell-test` 兩個 job

- `security-scan` job(原 docker-ci.yml 第 110–129 行)— 與 `security-scan.yml` 的 `trivy-security-scan` 重複
- `shell-test` job(原第 40–58 行)— 與 `script-test.yml` 重複

### 3.5 Commit

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/docker-ci.yml'))"
git add .github/workflows/docker-ci.yml
git commit -m "ci(docker-ci): align with team template (concurrency, permissions, basics, dedup)"
```

---

## Task 4 對應實作 — `docker-publish.yml`

> 對應 Plan: Task 4

### 4.1 在 `on:` 後、`jobs:` 前插入

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: false   # 推 tag 的 job 不可被新 push 中斷

permissions:
  contents: read
```

### 4.2 `publish:` job 內覆寫權限

```yaml
  publish:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write          # 推 image (若用 GHCR)
      id-token: write          # attest-build-provenance 需要
      attestations: write      # attest-build-provenance 需要
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
      # ... 其餘步驟保持不變
```

### 4.3 修 `steps.push.outputs.digest` 缺少 id 的 bug

```yaml
    - name: Build and push base image
      id: push                # ← 新增此行
      uses: docker/build-push-action@v6
      # ... 其餘不變
```

### 4.4 Commit

```bash
sed -i 's|actions/checkout@v6|actions/checkout@v4|g' .github/workflows/docker-publish.yml
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/docker-publish.yml'))"
git add .github/workflows/docker-publish.yml
git commit -m "ci(docker-publish): minimal permissions, fix push step id, pin checkout@v4"
```

---

## Task 5 對應實作 — 其餘 3 workflow

> 對應 Plan: Task 5

於 `script-test.yml` / `security-scan.yml` / `proxmox-k8s-ci.yml` 各自 `on:` 後插入(`security-scan.yml` 已有 permissions,只加 concurrency):

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
```

`script-test.yml` / `proxmox-k8s-ci.yml` 還要加:

```yaml
permissions:
  contents: read
```

所有 `actions/checkout@v6` → `@v4`:

```bash
for f in .github/workflows/{script-test,security-scan,proxmox-k8s-ci}.yml; do
  sed -i 's|actions/checkout@v6|actions/checkout@v4|g' "$f"
  python3 -c "import yaml; yaml.safe_load(open('$f'))" && echo "OK: $f"
done

git add .github/workflows/{script-test,security-scan,proxmox-k8s-ci}.yml
git commit -m "ci: add concurrency and minimal permissions to remaining workflows"
```

---

## Task 6 對應實作 — PR Labeler

> 對應 Plan: Task 6

### 6.1 複製 workflow

```bash
cp /e/source/team-project-template/.github/workflows/pr-labeler.yml \
   /d/app/docker-operation/.github/workflows/pr-labeler.yml
```

### 6.2 寫客製 `labeler.yml`

```yaml
# =============================================================================
# PR 自動標籤規則 (docker-operation 客製版)
# 使用 actions/labeler@v6 格式
# =============================================================================

docker:
  - changed-files:
      - any-glob-to-any-file:
          - '**/Dockerfile'
          - '**/Dockerfile.*'
          - '**/docker-compose*.yml'
          - '**/docker-compose*.yaml'
          - '.dockerignore'
          - '.hadolint.yaml'

scripts:
  - changed-files:
      - any-glob-to-any-file:
          - '**/*.sh'
          - '**/*.bash'
          - '**/*.bat'
          - '**/*.cmd'
          - '**/*.ps1'

nginx:
  - changed-files:
      - any-glob-to-any-file:
          - 'nginx/**'
          - 'nginx1.29.3-docker/**'

database:
  - changed-files:
      - any-glob-to-any-file:
          - 'DB/**'
          - '**/*.sql'
          - '**/migrations/**'

proxmox:
  - changed-files:
      - any-glob-to-any-file:
          - 'proxmox9.0/**'
          - 'proxmox-k8s/**'

ci/cd:
  - changed-files:
      - any-glob-to-any-file:
          - '.github/**'
          - 'tests/**'
          - 'Dockerfile/bump-version.*'

documentation:
  - changed-files:
      - any-glob-to-any-file:
          - '**/*.md'
          - 'docs/**'
          - 'README*'
          - 'LICENSE'

dependencies:
  - changed-files:
      - any-glob-to-any-file:
          - 'package.json'
          - 'package-lock.json'
          - 'requirements*.txt'

config:
  - changed-files:
      - any-glob-to-any-file:
          - '.editorconfig'
          - '.gitignore'
          - '.gitattributes'
          - '.shellcheckrc'
          - '.prettierrc*'
```

### 6.3 Commit

```bash
git add .github/workflows/pr-labeler.yml .github/labeler.yml
git commit -m "ci: add PR labeler with docker-operation specific rules"
```

---

## Task 7 對應實作 — `dependabot.yml`

> 對應 Plan: Task 7

### 7.1 整檔覆寫

```yaml
version: 2
updates:
  - package-ecosystem: github-actions
    directory: /
    schedule:
      interval: weekly
      day: monday
      time: "09:00"
      timezone: Asia/Taipei
    open-pull-requests-limit: 5
    labels:
      - dependencies
      - ci/cd
    commit-message:
      prefix: chore(ci)
      include: scope

  # 確認 nginx1.29.3-docker 真的有 Dockerfile 才保留;根目錄無 Dockerfile,故不放 directory: /
  - package-ecosystem: docker
    directory: /nginx1.29.3-docker
    schedule:
      interval: weekly
      day: monday
      time: "09:00"
      timezone: Asia/Taipei
    open-pull-requests-limit: 3
    labels:
      - dependencies
      - docker
      - nginx
    commit-message:
      prefix: chore(docker)
      include: scope
```

### 7.2 動態擴充其他子目錄

```bash
# 列出所有 Dockerfile 位置,依結果手動補 directory 區塊
find /d/app/docker-operation -name "Dockerfile" -not -path "*/.git/*" -not -path "*/Dockerfile/*"
```

### 7.3 Commit

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/dependabot.yml'))"
git add .github/dependabot.yml
git commit -m "ci(deps): align dependabot.yml with team template format"
```

---

## Task 8 對應實作 — PR template

> 對應 Plan: Task 8

### 8.1 複製並裁減

```bash
cp /e/source/team-project-template/.github/PULL_REQUEST_TEMPLATE.md \
   /d/app/docker-operation/.github/PULL_REQUEST_TEMPLATE.md
```

刪除段落:
- `## 📸 截圖 / 錄影`
- `## 🗃️ 資料庫變更`
- `## 🔌 API 變更`

`## 🎯 影響範圍` 改為:

```markdown
- [ ] Docker (compose / Dockerfile)
- [ ] Shell 腳本 (nginx / proxmox / DB 等)
- [ ] CI/CD (.github/)
- [ ] 文件
- [ ] 其他:
```

### 8.2 Commit

```bash
git add .github/PULL_REQUEST_TEMPLATE.md
git commit -m "docs: add PR template (adapted from team)"
```

---

## Task 9 對應實作 — Issue templates

> 對應 Plan: Task 9

### 9.1 複製三檔

```bash
mkdir -p /d/app/docker-operation/.github/ISSUE_TEMPLATE
cp /e/source/team-project-template/.github/ISSUE_TEMPLATE/{bug_report,feature_request,config}.yml \
   /d/app/docker-operation/.github/ISSUE_TEMPLATE/
```

### 9.2 微調 `bug_report.yml` 的 environment 欄位

```yaml
      value: |
        - 環境:[ ] 生產 / [ ] 測試 / [ ] 本地
        - Docker 版本:(docker --version)
        - Docker Compose 版本:(docker compose version)
        - 作業系統:(如 Debian 13 / Ubuntu 22.04 / Windows 11)
        - 涉及的子專案目錄:(如 nginx1.29.3-docker / DB/SQLServer)
        - 發生時間:YYYY-MM-DD HH:mm
```

### 9.3 `config.yml` 加 TODO 註解

```yaml
# TODO: 啟用前請替換以下兩項
#   - 團隊頻道 URL
#   - 資安通報信箱
```

### 9.4 Commit

```bash
for f in bug_report.yml feature_request.yml config.yml; do
  python3 -c "import yaml; yaml.safe_load(open('.github/ISSUE_TEMPLATE/$f'))" && echo "OK: $f"
done

git add .github/ISSUE_TEMPLATE/
git commit -m "docs: add issue templates (bug / feature / config)"
```

---

## Task 10 對應實作 — CODEOWNERS

> 對應 Plan: Task 10

```
# =============================================================================
# CODEOWNERS — PR 修改對應路徑時自動指派 reviewer
# TODO: 將下方 @TW199501 替換為實際維護者帳號或團隊
# =============================================================================

*                           @TW199501
/.github/                   @TW199501
/docs/                      @TW199501
**/Dockerfile               @TW199501
**/docker-compose*.yml      @TW199501
/Dockerfile/                @TW199501
```

```bash
git add .github/CODEOWNERS
git commit -m "docs: add CODEOWNERS placeholder"
```

---

## Task 11 對應實作 — Compose 命名規範

> 對應 Plan: Task 11

### 11.1 `docs/conventions/compose-naming.md`

完整內容見 Plan 文件中 Task 11 段落引用(過長省略,複製即可)。

### 11.2 違規 reference 報告腳本

```bash
cd /d/app/docker-operation
for f in pgbackup-compose.yml docker-compose-pg.yml docker-compose-mssql.yml \
         compose-nginx-ui.yml nginx-ui-compose.yml docker-compose-6card.yml; do
  echo "=== $f ==="
  grep -rn --include='*.md' --include='*.sh' --include='*.yml' --include='*.yaml' \
       --include='*.bat' --include='*.cmd' --include='*.ps1' \
       -- "$f" . 2>/dev/null | grep -v "^\\./\\.git/" || echo "(no references)"
  echo
done
```

### 11.3 CLAUDE.md 段落(於 `## House rules` 之前插入)

```markdown
## Compose 檔命名規範

**規則(完整版見 `docs/conventions/compose-naming.md`):**
- 子目錄名表達專案 → compose 檔名**不重複**專案名。
- 預設:`docker-compose.yml`。
- 變體:**點分隔** — `docker-compose.<env>.yml`(`dev / test / staging / prod`)或 `docker-compose.<purpose>.yml`。
- 禁止:`compose-X.yml` / `X-compose.yml` / `docker-compose-X.yml`(dash)。
```

### 11.4 docker-ci.yml basics job advisory step

```yaml
      - name: Check docker-compose file naming convention (advisory)
        continue-on-error: true
        run: |
          BAD=$(find . -type f \
                  \( -name "compose-*.yml" -o -name "compose-*.yaml" \
                     -o -name "*-compose.yml" -o -name "*-compose.yaml" \
                     -o -name "docker-compose-*.yml" -o -name "docker-compose-*.yaml" \) \
                  -not -path "./.git/*" || true)
          if [ -n "$BAD" ]; then
            echo "::warning::以下 compose 檔不符合團隊命名規範(見 docs/conventions/compose-naming.md):"
            echo "$BAD" | while read -r f; do echo "::warning::  $f"; done
          else
            echo "✅ 所有 compose 檔皆符合命名規範"
          fi
```

### 11.5 Commit

```bash
git add docs/conventions/compose-naming.md CLAUDE.md .github/workflows/docker-ci.yml
git commit -m "docs(conventions): document compose naming rule and add advisory CI check"
```

---

## Task 12 對應實作 — `.env` / secrets

> 對應 Plan: Task 12

### 12.1 `.gitignore` 環境/機密區塊改為

```gitignore
# ---------- 環境變數 / 機密(對齊團隊規範) ----------
.env
.env.local
.env.*.local
!.env.example
*.pem
*.key
*.pfx
secrets/
```

### 12.2 `.dockerignore` 對應段落改為

```dockerignore
# ---------- 機密 / 環境(對齊團隊規範) ----------
.env
.env.*
!.env.example
*.pem
*.key
*.pfx
secrets/
```

### 12.3 修 typo

```bash
git mv gitea/.env.exampke gitea/.env.example
```

### 12.4 確認無 `.env` 已 tracked

```bash
git ls-files | grep -E '(^|/)\.env($|\.)' | grep -v '\.env\.example$'
# 期待:無輸出。若有,暫停回報 user(history rewrite 是破壞性)。
```

### 12.5 docker-ci.yml basics job 強制阻擋 step(雙重)

```yaml
      - name: Block .env and secret files (must not be committed)
        run: |
          BAD=$(git ls-files | grep -E '(^|/)(\.env($|\.)(?!example$)|.*\.pem$|.*\.key$|.*\.pfx$)' \
                | grep -vE '(^|/)\.env\.example$' || true)
          if [ -n "$BAD" ]; then
            echo "::error::偵測到禁止進 Git 的機密/環境檔:"
            echo "$BAD" | while read -r f; do echo "::error::  $f"; done
            echo "::error::處理方式:"
            echo "::error::  1. git rm --cached <檔案>"
            echo "::error::  2. 將檔案中的秘密 revoke + 重設(視為已洩漏)"
            echo "::error::  3. .env 改放 .env.example 留範例,實際值由部署環境注入"
            exit 1
          fi
          echo "✅ 無禁止檔案進 Git"

      - name: Block secrets in newly added files (PR only)
        if: github.event_name == 'pull_request'
        run: |
          ADDED=$(git diff --name-only --diff-filter=A "${{ github.event.pull_request.base.sha }}" "${{ github.event.pull_request.head.sha }}" || true)
          BAD=$(echo "$ADDED" | grep -E '(^|/)(\.env($|\.)|.*\.pem$|.*\.key$|.*\.pfx$)' | grep -vE '(^|/)\.env\.example$' || true)
          if [ -n "$BAD" ]; then
            echo "::error::本 PR 新增了禁止進 Git 的機密/環境檔:"
            echo "$BAD" | while read -r f; do echo "::error::  $f"; done
            exit 1
          fi
          echo "✅ 本 PR 未新增機密檔案"
```

### 12.6 Commit

```bash
git add .gitignore .dockerignore .github/workflows/docker-ci.yml gitea/.env.example
git commit -m "chore(security): align .env/secret ignore rules with team and enforce in CI"
```

---

## Task 13 對應實作 — 全域驗證 + 推送

> 對應 Plan: Task 13

```bash
cd /d/app/docker-operation

# 列 commit
git log --oneline main..HEAD   # 約 15 個 commit(Task 0 兩個 + Task 1–13 各一個)

# 全 YAML 驗證
find .github -name "*.yml" -o -name "*.yaml" | while read f; do
  python3 -c "import yaml; yaml.safe_load(open('$f'))" && echo "OK: $f" || echo "FAIL: $f"
done

# line-ending 終驗
node .github/scripts/check-line-endings.mjs

# 推送(待 user 同意才執行)
git push -u origin chore/ci-align-team-template
```
