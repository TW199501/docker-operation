# PR Description — chore/env-conventions

> **複製從 `## Summary` 開始的內容貼到 GitHub PR 表單**
> **base branch:** `main`(等 `chore/ci-align-team-template` 先合進 main、本分支 rebase 後再開)

---

## Summary

定義 `.env` / `.env.example` 命名規範,寫 bootstrap 工具鏈把 `your_secure_password_here` 之類的字面佔位**改成 shell command substitution**,跑 `bootstrap-env.sh` 自動生成強密碼。

涵蓋 8 個 Task:

- 緊急處理 `gitea/.env.example` 兩處字面密碼 `Elf23887711`(user 確認 Case A 純文件範例)
- 文件:`docs/conventions/env-naming.md` 5 條語法規則 + 命令白名單
- 工具:`scripts/env/bootstrap-env.sh`(完整版:白名單 / `--force` / `--dry-run` / `--non-interactive` / `--all`)
- 測試:`tests/env/test_bootstrap.bats` 7 case
- CI:`check-env-syntax.sh`(強制擋字面密碼 + 白名單外命令)
- CI:`check-env-coverage.sh`(advisory,49 → 47 個 example ↔ compose 覆蓋缺口)
- 改寫 11 個既有 `.env.example` 對齊規範

> 詳細策略 / 設計動機見 [`docs/superpower/plan/2026-05-28-env-conventions.md`](docs/superpower/plan/2026-05-28-env-conventions.md)
> 實作細節見 [`docs/superpower/spec/2026-05-28-env-conventions.md`](docs/superpower/spec/2026-05-28-env-conventions.md)

---

## 核心模型

```
.env.example(進 git,只放 $(openssl rand) 等生成語法)
     │
     ▼
scripts/env/bootstrap-env.sh
     │
     ▼
.env(不進 git,bootstrap 展開真實值後產出)
     │
     ▼
docker-compose up -d
```

## 5 條語法規則(完整見 `docs/conventions/env-naming.md`)

1. **字面值**:`TZ=Asia/Taipei`
2. **自動生成**:`PASSWORD=$(openssl rand -base64 32)` — 命令必須在白名單
3. **必填空值**:`ADMIN_EMAIL=` — bootstrap 互動 prompt
4. **含空格必引號**:`APP_NAME="My App"`
5. **註解用 `#`**(禁 `//` C-style)

## 命令白名單

`openssl` / `uuidgen` / `date` / `hostname` / `cat` / `tr` / `head` / `tail` / `echo` / `printf`

**禁止**:`curl` / `wget` / `bash` / `eval` / 任何網路命令(`.env.example` 進 git = attack surface)

---

## Commits(8 個)

| # | Commit | 內容 |
|---|---|---|
| Plan+Spec | `78097da` | 加 Plan / Spec 文件 |
| Task 0 | `f5a2974` | 移除 `gitea/.env.example` 兩處 `Elf23887711` + 整檔重組(// → #) |
| Task 1 | `1a1d22f` | `docs/conventions/env-naming.md` + template + `CLAUDE.md` 段落 |
| Task 2 | `6e5b068` | `scripts/env/{bootstrap-env.sh, lib/whitelist.sh, lib/parse.sh, README.md}` |
| Task 3 | `2f901a8` | Bats 測試 7 case + `run_all_tests.sh` hook |
| Task 4 | `e191098` | CI step:`check-env-syntax.sh`(強制) |
| Task 5 | `63c39ab` | CI step:`check-env-coverage.sh`(advisory,warn-only) |
| Task 6 | `ab8f85a` | 改寫 10 個 `.env.example`(gitea 已在 Task 0 處理) |

---

## Definition of Done

- ✅ 11 個 `.env.example` 全部符合規範
- ✅ `bootstrap-env.sh` 本機驗證:正常路徑 / 白名單擋 `$(curl ...)` / skip 已存在 / `--force` backup / `--dry-run` 不寫檔 / `--non-interactive` 空值失敗
- ✅ CI `check-env-syntax`:11 個 example 全綠(原本 2 個違規清零)
- ✅ CI `check-env-coverage`:advisory 跑出 47 個剩餘缺口(屬 compose 不同步,另案)
- ✅ `gitea/.env.example` 兩處 `Elf23887711` 已清(user 確認 Case A:純文件範例,從未實際使用)

---

## 緊急安全處理

- `gitea/.env.example:20` `DB_PASSWD=Elf23887711` 與 `:31` SQL `'Elf23887711'` 已移除
- user 確認:**Case A — 純文件範例,從未在任何環境實際使用**(無需 revoke / history rewrite)
- 原檔同時混雜 `// C-style 註解` 與 shell / SQL 命令,bash source 會在 line 29 `sudo chown` 直接炸,本 PR 整檔重組

---

## 不在範圍(留 follow-up Plan)

- 47 個 coverage 缺口(buildingai / DB/mariadb / gitea/runner 等 compose ↔ example 不同步)
- coverage advisory 轉強制(等 47 個缺口處理完)
- Bootstrap 對接 Vault / Bitwarden(超出本 repo 規模需求)
- PowerShell 版 bootstrap
- ollama 目錄重構(user 已提出,另立 Plan)

---

## Test plan

- [ ] CI:`docker-ci.yml > basics job > Check .env.example syntax` 通過
- [ ] CI:`docker-ci.yml > basics job > Check .env.example covers compose variables` 跑(會 warn 但不擋)
- [ ] CI:Bats(若 runner 有 bats 環境)
- [ ] 本機:`./scripts/env/bootstrap-env.sh --dry-run --non-interactive DB/POSTGRES` 產出含 base64 密碼的 `.env`

🤖 Generated with [Claude Code](https://claude.com/claude-code)
