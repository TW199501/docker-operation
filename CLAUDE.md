# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository nature

This is **not** a single application. It is a mono-repo of independent Docker / infra "stacks", one per top-level directory (e.g. `nginx/`, `nginx1.29.3-docker/`, `DB/SQLServer/`, `DB/POSTGRES/`, `certbot/`, `proxmox9.0/`, `proxmox-k8s/`, `cloudflare/`, `keepalived/`, `dockge/`, `bytebase/`, `chatwoot/`, `immich/`, ...).

Each stack is self-contained — its own `docker-compose.yml`, sometimes its own `Dockerfile`, often its own README. The "code" is almost entirely **Bash scripts + Compose YAML + Dockerfiles**; there is no application source to compile.

Implication for changes: scope work to a single stack directory unless the user explicitly says otherwise. Don't refactor across stacks, and don't assume utilities in one stack apply to others.

## Common commands

All commands assume you `cd` into the relevant stack directory first (e.g. `cd nginx1.29.3-docker`), unless otherwise stated.

### Per-stack lifecycle
```bash
docker-compose config --quiet            # validate compose syntax for the stack
docker compose up -d                     # start the stack
docker compose -f docker-compose.build.yml up -d --build   # used by nginx1.29.3-docker
docker compose ps
docker compose logs -f <service>
```

### Repo-wide validation (run from repo root)
```bash
# Validate every docker-compose file in the repo
find . -name "docker-compose*.yml" -o -name "docker-compose*.yaml" | while read -r f; do
  echo "Validating $f"; docker-compose -f "$f" config --quiet || echo "Warning: $f has issues"
done

# Shell scripts: syntax + lint
find . -name "*.sh" -type f -exec bash -n {} \;
find . -name "*.sh" -type f -exec shellcheck {} \;

# Dockerfiles
docker run --rm -i hadolint/hadolint < Dockerfile      # one file at a time
```

### Custom test framework (`tests/`)
```bash
cd tests
bash run_all_tests.sh                    # all enabled tests (driven by test-config.ini)
bash run_all_tests.sh unit               # unit only
bash run_all_tests.sh integration        # docker-compose checks
bash run_all_tests.sh e2e
bash run_all_tests.sh -v all             # verbose
bash run_all_tests.sh -o report.txt all  # write report
```
Notes:
- The runner reads `tests/test-config.ini` for which suites are enabled. An explicit type argument (e.g. `unit`) runs that suite even if disabled in config — the runner just warns.
- `tests/run_all_tests.sh` shells out to specific test scripts (`test_prefix_to_netmask.sh`, `test_docker_compose.sh`, `test_e2e.sh`). When adding a new test, also wire it into the matching `run_*_tests` function in `run_all_tests.sh`.

### Version bump (whole-repo, not per-stack)
```bash
cd Dockerfile
./bump-version.sh           # patch  (X.Y.Z -> X.Y.Z+1)
./bump-version.sh minor     # X.Y.0  -> X.(Y+1).0
./bump-version.sh major     # (X+1).0.0
# Windows: bump-version.bat ...
```
This script does **all of the following in one go**, then leaves the push to you:
1. Bumps `Dockerfile/VERSION`.
2. Rewrites `LABEL version=...` in every `*/Dockerfile` across the repo via `sed`.
3. `git add VERSION */Dockerfile`, creates a commit `Bump version to X.Y.Z`, and creates an annotated tag `vX.Y.Z`.

Do **not** hand-edit `Dockerfile/VERSION` or sprinkle different versions across sub-projects — the whole repo shares one version and one tag stream, and CI's `docker-publish.yml` is driven off the `v*` tag.

## CI / GitHub Actions

Workflows live in `.github/workflows/`:

- `docker-ci.yml` — `main`/`develop` push 或 `main` PR 觸發,path filter 含 `**/Dockerfile` / `**/docker-compose*.yml` / `**/*.sh` / `.github/workflows/**` / `.github/scripts/**` / `**/.env.example`。Jobs:
    - **`basics`**(新增,對齊團隊範本)— Conventional Commits 檢查(PR to main)、line-ending(`node .github/scripts/check-line-endings.mjs`)、大檔(>5MB)、compose 命名 advisory(warn-only)、**`.env`/secrets 強制阻擋**(`git ls-files` 雙重檢查 + PR diff)、`.env.example` syntax + 命令白名單(強制)、coverage advisory。
    - `docker-lint`(Hadolint)/ `docker-compose-validate`(`config --quiet`)/ `build-test`(若根有 Dockerfile)/ `version-check`(README.md vs `Dockerfile/VERSION`)
    - **已移除**:`security-scan` job(改由 `security-scan.yml` 集中跑 Trivy);`shell-test` job(改由 `script-test.yml`)。
- `script-test.yml` — `**/*.sh` / `**/*.bash` 改動觸發。Shellcheck + `bash -n`。
- `docker-publish.yml` — `v*` tag(由 `bump-version.sh` 建)或 GitHub Release 觸發。Buildx + multi-arch(amd64/arm64) → Docker Hub(`secrets.DOCKER_USERNAME` / `DOCKER_PASSWORD`)+ `attest-build-provenance`(需 `id: push` 引用,2026-05-28 修正完成)。`concurrency.cancel-in-progress: false`(推送不可被中斷)。**只 build 根目錄的 Dockerfile**(目前根無 Dockerfile,workflow 只在實際有人放進來時才會跑出結果);sub-stack Dockerfile 不 auto-publish。
- `pr-labeler.yml` — `pull_request_target` 自動套 label(規則於 `.github/labeler.yml`)。⚠️ 安全敏感:**禁止**在此 workflow checkout PR 程式碼後執行任何 script(pwn-request 攻擊面)。
- `security-scan.yml` — Trivy fs / Docker config scan、gitleaks、CodeQL(`languages: actions`,2026-05-28 從 `javascript, python` 改正)。**GitHub Default setup 已 disable**(透過 `gh api -X PATCH repos/<owner>/<repo>/code-scanning/default-setup -f state=not-configured`,否則 Default 會跟 advanced 衝突)。
- `proxmox-k8s-ci.yml` — `proxmox-k8s/` 子目錄專用 shellcheck + smoke test。

**All workflows 已加 `concurrency` + 最小 `permissions`**(2026-05-28 對齊團隊範本)。所有 `actions/checkout` 統一 `@v4`(`@v6` 不存在,曾有此誤值)。

Note: 根目錄還有 `.github-*.yml` 4 個檔(`.github-docker-workflows.yml`、`.github-dependabot.yml` 等)— 這些是 **templates/backups**,active workflows 在 `.github/workflows/`。改 root-level 的不會影響 CI。

## Linter configuration (important when fixing CI failures)

- `.hadolint.yaml` — disables `DL3003, DL3006, DL3008, DL3013, DL3018, DL3025, DL3042, DL3059`. So "pin apt/pip/apk versions" and "don't run as root" warnings are intentionally suppressed; don't add those pins just to silence the linter.
- `.shellcheckrc` — globally disables `SC2034, SC2028, SC2116, SC2086, SC2004, SC2153, SC2148, SC1017, SC1090, SC1091, SC2154, SC2164`. Unquoted variable expansions (`SC2086`) and sourced-file checks (`SC1091`) will not flag — don't add quotes/`# shellcheck source=` purely to please the linter. Enabled extras: `add-default-case`, `avoid-nullary-conditions`, `check-unassigned-uppercase`.
- `.editorconfig` — LF line endings, UTF-8, 2-space indent, trim trailing whitespace (except `*.md`).
- `.gitattributes` — **全域 LF**(包括 Windows checkout 也轉);**只有** `.bat` / `.cmd` / `.ps1` 強制 CRLF。CI 用 `.github/scripts/check-line-endings.mjs` 強制。本機若編輯後行尾跑掉,跑 `git ls-files --eol -z | tr '\0' '\n' | awk -F'\t' '$1 ~ /w\/crlf/ {print $2}' | xargs -I{} sed -i 's/\r$//' {}` 一次性 normalize 同時保留 `.bat` 的 CRLF。
- `.dockerignore` — 已對齊團隊規範:`.env` / `.env.*` + `!.env.example` 例外 + `*.pem` / `*.key` / `*.pfx` / `secrets/`。
- `.gitignore` — 同上;額外擋 `.env.local` / `.env.*.local`。

## Stack-specific notes

- `nginx1.29.3-docker/` is the most elaborate stack: custom-compiled Nginx 1.29.3 image with GeoIP2 / Brotli / ModSecurity / headers-more / cache-purge / njs, plus HAProxy + Keepalived. Build with `docker compose -f docker-compose.build.yml build`. Detailed docs live in `nginx1.29.3-docker/docs/`. There is a `build-nginx.sh請勿修改.backup` file — the filename literally says "do not modify"; treat it as a frozen reference.
- `nginx/` (different from above) holds the orchestration & install scripts (`00-preflight-nginx.sh` → `25-nginxwebui-install.sh`, numbered to indicate run order) plus firewall / IP-list / Cloudflare update helpers. Sites live under `nginx/sites-available/`.
- `Dockerfile/` is **not** a Dockerfile — it's the versioning subsystem (`VERSION`, `bump-version.sh`, `bump-version.bat`, `VERSIONING.md`). The repo root has no Dockerfile by default.
- `proxmox9.0/` and `proxmox-k8s/` are Proxmox host-side provisioning scripts, not container workloads. `proxmox-k8s/Makefile` is the entry point there (`make help`).
- `DB/` groups database stacks (`POSTGRES/`, `SQLServer/`, `mariadb/`, `redis/`, `Qdrant/`, `sql2022/`, `dbtools/`). Backups: see e.g. `DB/POSTGRES/pg-backup.sh`.
- `certbot/bootstrap-certificates.sh` issues certs via the Cloudflare DNS-01 plugin; it expects `certbot/cloudflare.ini` (see `cloudflare.ini.example`).

## Compose 檔命名規範

**規則(完整版見 [`docs/conventions/compose-naming.md`](docs/conventions/compose-naming.md)):**
- 子目錄名表達專案 → compose 檔名**不重複**專案名。
- 預設:`docker-compose.yml`。
- 變體:**點分隔** — `docker-compose.<env>.yml`(`dev / test / staging / prod`)或 `docker-compose.<purpose>.yml`(`build / backup / ui`)。
- 禁止:`compose-X.yml` / `X-compose.yml` / `docker-compose-X.yml`(dash 而非 dot)。

**動本目錄的 compose 檔時**:先 `grep -rn <檔名> .` 確認 reference;改名須同步更新所有 caller(docs / shell scripts / CI workflows)。
**新增 compose 檔時**:遵循上述規則,違反會被 CI advisory 警告(目前 warn-only;待現存 6 個違規檔處理完後轉強制)。

## .env 命名規範

**完整規範:** [`docs/conventions/env-naming.md`](docs/conventions/env-naming.md)

**核心模型:** `.env.example`(進 git)→ `scripts/env/bootstrap-env.sh` → `.env`(不進 git)→ docker-compose

`docker-compose` 預設**只讀 `.env`,不會展開 `$(...)`**;務必先跑 bootstrap。沒 `.env` 時 compose 對 `${VAR}` 展開為空字串並印 warning,但 `config --quiet` 仍 exit 0(這是測試框架的盲點 — 別假設 `test_docker_compose.sh` 過了就代表 stack 能 up)。

**5 條語法:**
- 字面值:`TZ=Asia/Taipei`
- 自動生成:`PASSWORD=$(openssl rand -base64 32)` — 命令必須在白名單內(`openssl` / `uuidgen` / `date` / `hostname` / `cat` / `tr` / `head` / `tail` / `echo` / `printf`,**禁** `curl` / `wget` / `bash` / `eval`)
- 必填空值:`ADMIN_EMAIL=` — bootstrap 互動 prompt
- 含空格必引號:`APP_NAME="My App"`
- 註解用 `#`(**禁** `//` C-style — bash source 會把後段當值)

**Bootstrap 用法**:
```bash
./scripts/env/bootstrap-env.sh DB/POSTGRES                    # 對單一 stack
./scripts/env/bootstrap-env.sh --dry-run DB/POSTGRES          # 預覽不寫
./scripts/env/bootstrap-env.sh --force DB/POSTGRES            # 覆寫並 backup
./scripts/env/bootstrap-env.sh --non-interactive DB/POSTGRES  # CI 用,空值不 prompt
./scripts/env/bootstrap-env.sh --all                          # 全 repo
```

**CI 強制(`docker-ci.yml > basics`)**:
- `scripts/env/check-env-syntax.sh` — 白名單 + 字面密碼 heuristic;**擋 PR**
- `scripts/env/check-env-coverage.sh` — compose `${VAR}` 是否在 example 有定義;**advisory**(現有 47 個缺口,見 §Open follow-ups)

## Documentation conventions(Plan + Spec 雙檔 / Memory 規範)

本 repo 採用「**Plan + Spec 雙檔**」結構記錄非 trivial 的實作計畫(對齊 `e:\source\team-project-template\docs\superpower\`):

- `docs/superpower/plan/YYYY-MM-DD-<feature>.md` — **策略層**:動機、責任邊界、Task 列表、執行節奏、取捨點、風險、DoD、Out of Scope、Follow-up、待回答問題。**不**含實作代碼。
- `docs/superpower/spec/YYYY-MM-DD-<feature>.md` — **實作層**:每 Task 對應的代碼、schema、API、指令。標題用 `## Task N — ...` + 開頭 `> 對應 Plan: Task N`。
- 兩檔同名(只差子目錄),開頭互相 link。

**Task 結構**:Plan / Spec 子單元一律叫 **Task**(不用 Phase / Stage)。每個 Task 結尾以**一次 `git commit`** 收斂(顆粒度:一個邏輯單元 = 一個 commit)。

**Memory**:`docs/superpower/memory/` 含 feedback / project 記憶檔,索引在 `MEMORY.md`。**禁止**寫到全域 `~/.claude/projects/<repo>/memory/` — memory 必須跟 repo 走。

現存規範記憶:
- [`feedback_plan_structure.md`](docs/superpower/memory/feedback_plan_structure.md) — Plan → Task
- [`feedback_plan_spec_split.md`](docs/superpower/memory/feedback_plan_spec_split.md) — 雙檔對應
- [`feedback_memory_location.md`](docs/superpower/memory/feedback_memory_location.md) — memory 一律專案路徑

## Repo settings(已用 `gh api` 設好,**勿在 GitHub UI 改回**)

- **Code scanning Default setup**:`disabled`(避免跟 `security-scan.yml` 的 advanced workflow 衝突;GitHub 規定 default 開啟時 advanced 結果會被丟掉)
  ```bash
  gh api repos/<owner>/<repo>/code-scanning/default-setup                          # 查狀態
  gh api -X PATCH repos/<owner>/<repo>/code-scanning/default-setup -f state=not-configured
  ```

## Open follow-ups(未做完的事項)

依執行優先順序:

1. **Compose mass rename(6 個違規檔)** — `DB/POSTGRES/pgbackup-compose.yml` / `gitea/docker-compose-pg.yml` / `gitea/runner/docker-compose-mssql.yml` / `nginx/compose-nginx-ui.yml` / `nginx1.29.3-docker/nginx-ui-compose.yml` / `ollama/docker-compose-6card.yml`。其中 `nginx-ui-compose.yml` 有 7 個 markdown reference(README / docs),改名需同步。完整清單見 [`docs/conventions/compose-naming.md`](docs/conventions/compose-naming.md)。
2. **`.env.example` ↔ compose coverage 49 個缺口** — 主要在 `buildingai/` / `DB/mariadb/` / `gitea/` / `gitea/runner/`(沒 `.env.example` 但 compose 用 `${VAR}`)。`bash scripts/env/check-env-coverage.sh` 列完整清單。
3. **`compose-naming.md` advisory 轉強制** — 待 (1) 處理完;移除 `docker-ci.yml > basics > Check docker-compose file naming convention` 的 `continue-on-error: true`。
4. **`check-env-coverage.sh` advisory 轉強制** — 待 (2) 處理完。
5. **CODEOWNERS 從個人 `@TW199501` 改團隊 group** — 等 GitHub Team 建好。
6. **`.github/ISSUE_TEMPLATE/config.yml`** TODO — `YOUR-TEAM-CHANNEL-URL` / `security@YOUR-DOMAIN` 待填。
7. **`ollama/` 目錄重構** — user 已提出但範圍未定;可能涉及 image 版本、GPU 設定、刪 `Untitled-1.md` scratch、改 `docker-compose-6card.yml`。

## Active branches(本地 + remote)

- `chore/ci-align-team-template` — 14+ commits,**對齊團隊範本** + 修隱性 bug(`docker-publish.yml > id: push`);**待 merge 進 main**
- `chore/env-conventions` — 8+ commits,**`.env` 規範 + bootstrap 工具鏈**;依賴前者,**先合前者再 rebase**

兩個 PR 都動 `docker-publish.yml` / `security-scan.yml`,跟 Dependabot PR #14-#18 會 conflict;合進 main 後 dependabot 下週重開 PR(或手動 close + retrigger)。

## House rules

> 來源是已移除的 `.windsurf/rules/ai-commitment-statement.md`(於 `chore/ci-align-team-template` 分支 Task 0 刪除),但規則本身保留:

- Follow explicit user instructions exactly. Don't introduce unrequested refactors or "improvements".
- When the user asks to copy a block from file A to file B, copy verbatim — don't reformat, don't touch surrounding code in either file.
- Keep diffs as small as possible — touch only the section required.
- Report changes by file + line range + a one-line description. Don't re-paste the user's existing code back at them.
- Don't proactively "teach" or explain unless asked.

額外規則(本 session 累積):

- **使用 `gh` CLI 處理 GitHub repo settings** 而非要求 user 去 UI 點。如 disable Code scanning Default setup、查/改 dependabot 設定、列 PR/run 狀態等都用 `gh api` / `gh run` / `gh pr` 直接打。
- **動 .env.example 前先確認規範**:看 `docs/conventions/env-naming.md`;**禁** `your_xxx_here` 之類字面佔位、`${VAR}` 自我展開、`KEY=KEY` 重複名(這 3 種都被 `check-env-syntax.sh` heuristic 擋)。
- **改 `.github/workflows/*.yml` 後**:本機跑 `python -c "import yaml; yaml.safe_load(open(f, encoding='utf-8'))"` 只驗 syntax,**驗不出 workflow 業務邏輯**(如 CodeQL 配置語言不存在於 repo)。runtime-only 問題只能等 push 上去看,別在 commit message 寫「已驗證 CI 會過」直到真的看到綠燈。
