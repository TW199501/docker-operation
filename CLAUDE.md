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

- `docker-ci.yml` — runs on push/PR to `main`/`develop` when `**/Dockerfile`, `**/docker-compose*.yml`, or `**/*.sh` change. Jobs: Hadolint, ShellCheck + `bash -n`, `docker-compose config`, Trivy fs scan, version-consistency check against `README.md`.
- `script-test.yml` — triggered by changes to `**/*.sh` / `**/*.bash`.
- `docker-publish.yml` — triggered by `v*` tags (created by `bump-version.sh`) and GitHub Releases. Builds + pushes to Docker Hub (multi-arch amd64/arm64) using secrets `DOCKER_USERNAME` / `DOCKER_PASSWORD`. Only builds the **root** `Dockerfile` if one exists — sub-stack Dockerfiles are not auto-published.
- `proxmox-k8s-ci.yml`, `security-scan.yml` — additional checks.

Note: there are also `.github-*.yml` files at the repo **root** (e.g. `.github-docker-workflows.yml`, `.github-dependabot.yml`). These are templates/backups — the *active* workflows are the ones under `.github/workflows/` and `.github/dependabot.yml`. Don't edit the root-level `.github-*.yml` expecting CI to pick them up.

## Linter configuration (important when fixing CI failures)

- `.hadolint.yaml` — disables `DL3003, DL3006, DL3008, DL3013, DL3018, DL3025, DL3042, DL3059`. So "pin apt/pip/apk versions" and "don't run as root" warnings are intentionally suppressed; don't add those pins just to silence the linter.
- `.shellcheckrc` — globally disables `SC2034, SC2028, SC2116, SC2086, SC2004, SC2153, SC2148, SC1017, SC1090, SC1091, SC2154, SC2164`. Unquoted variable expansions (`SC2086`) and sourced-file checks (`SC1091`) will not flag — don't add quotes/`# shellcheck source=` purely to please the linter. Enabled extras: `add-default-case`, `avoid-nullary-conditions`, `check-unassigned-uppercase`.
- `.editorconfig` — LF line endings, UTF-8, 2-space indent, trim trailing whitespace (except `*.md`).

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

**5 條語法:**
- 字面值:`TZ=Asia/Taipei`
- 自動生成:`PASSWORD=$(openssl rand -base64 32)` — 命令必須在白名單內
- 必填空值:`ADMIN_EMAIL=` — bootstrap 互動 prompt
- 含空格必引號:`APP_NAME="My App"`
- 註解用 `#`(**禁** `//` C-style — bash source 會把後段當值)

**Bootstrap 一行起新環境:** `./scripts/env/bootstrap-env.sh DB/POSTGRES`

## House rules carried over from `.windsurf/rules/ai-commitment-statement.md`

These were authored as project-wide guidance for AI assistants and apply here too:

- Follow explicit user instructions exactly. Don't introduce unrequested refactors or "improvements".
- When the user asks to copy a block from file A to file B, copy verbatim — don't reformat, don't touch surrounding code in either file.
- Keep diffs as small as possible — touch only the section required.
- Report changes by file + line range + a one-line description. Don't re-paste the user's existing code back at them.
- Don't proactively "teach" or explain unless asked.
