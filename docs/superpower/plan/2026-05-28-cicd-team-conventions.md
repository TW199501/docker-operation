# CI/CD 對齊團隊規範 Plan — 策略層

> **類型:** Plan(策略層)
> **建立日期:** 2026-05-28
> **對應 Spec:** [`../spec/2026-05-28-cicd-team-conventions.md`](../spec/2026-05-28-cicd-team-conventions.md)
> **狀態:** Draft — 待 user(Tech Lead 代理) approve

---

## 1. 動機與背景

本 repo `D:\app\docker-operation` 是 Docker 應用 mono-repo,半年前獨立發展,CI/CD 散落 5 個 workflow,有重複(shellcheck 跑 3 次、Trivy 跑 2 次)、無 `concurrency`、無最小 `permissions`、`actions/checkout` 鎖到 `v6`(實際無此版本)。

團隊範本 `E:\source\team-project-template\.github` 已統一一套基線,包含:

- 工作流結構(concurrency / 最小 permissions / basics job / Conventional Commits / 大檔偵測)
- PR 自動標籤、PR template、Issue templates、CODEOWNERS
- 行尾規範(全域 LF,Windows 批次檔 CRLF)+ CI 強制執行腳本
- Dependabot 標準格式(timezone / scope / labels)

**本 Plan 把上述團隊規範套到本 repo,專注「跟 Docker 相關的工作流」**,並加上兩條 user 補的規範:

1. Compose 檔命名統一(`docker-compose.<env>.yml`,目錄名表達專案,不重複)
2. `.env` / secrets 不可進 Git,**CI 強制阻擋**

---

## 2. 責任邊界

| # | 需求 | 影響層 | 是否破壞既有功能 |
| --- | --- | --- | --- |
| R1 | Git 環境清理 | worktree / branch 狀態 | 否(暫存無關變動,刪除 stale residue) |
| R2 | 行尾規範 | 全 repo text 檔 | 風險:renormalize 動到大量檔(本 Plan 先 dry-run) |
| R3 | Workflows 對齊 | `.github/workflows/*.yml` 全部 | 否,只加 concurrency / permissions / pin version |
| R4 | PR/Issue 治理 | `.github/{PULL_REQUEST_TEMPLATE.md, ISSUE_TEMPLATE/, CODEOWNERS, labeler.yml, workflows/pr-labeler.yml}` | 否(全新增) |
| R5 | Dependabot 對齊 | `.github/dependabot.yml` | 否(重寫格式) |
| R6 | Compose 命名規範 | 文件 + advisory CI(不擋 PR) | 否(僅警告,改名需另案) |
| R7 | `.env` / secrets 規範 | `.gitignore` / `.dockerignore` / docker-ci.yml | **可能擋住既有 PR**(若有 .env 不慎進 git) — 但盤點已確認沒有 |

**相依鏈:**
- R1(Git 清理) 必須最先,否則 stash / branch 切換會亂
- R2(行尾)獨立,但 R3 的 line-ending CI step 依賴 R2 的 `.gitattributes`
- R3 內 `docker-ci.yml` 重寫**最重**,其他 workflow 只是補 concurrency
- R4 / R5 / R6 / R7 互相獨立
- R6 的 advisory CI step + R7 的強制阻擋 step 都加在 R3 已建好的 `basics` job

---

## 3. 總體架構衝擊圖

```
┌────────────────────────────────────────────────────────────┐
│  .github/workflows/docker-ci.yml(Task 3 重寫的核心)         │
│  ├─ basics job(新增)                                       │
│  │   ├─ Conventional Commits 檢查(main PR)                 │
│  │   ├─ Line-ending 檢查 ←── .github/scripts/check-line-endings.mjs(Task 2)
│  │   │                       └─ 規範來源 .gitattributes(Task 1)
│  │   ├─ 大檔偵測 (>5MB)
│  │   ├─ Compose 命名 advisory(Task 11,warn-only)
│  │   └─ .env / secrets 阻擋(Task 12,hard-block)
│  ├─ docker-lint / docker-compose-validate / build-test / version-check(保留)
│  │
│  .github/workflows/{docker-publish, script-test,            │
│                     security-scan, proxmox-k8s-ci}.yml      │
│  └─ 都補:concurrency + 最小 permissions + checkout@v4       │
│
│  .github/workflows/pr-labeler.yml(Task 6 新增)              │
│  └─ 讀 .github/labeler.yml(docker-operation 客製)           │
│
│  .github/{PULL_REQUEST_TEMPLATE.md, ISSUE_TEMPLATE/,         │
│           CODEOWNERS}(Task 8/9/10 新增)                     │
│
│  .github/dependabot.yml(Task 7 重寫)                        │
│  └─ github-actions + docker (nginx1.29.3-docker)            │
│
│  docs/conventions/compose-naming.md(Task 11 新增)           │
│  └─ 規範來源,advisory CI 警告引用此檔                       │
│
│  CLAUDE.md(已存在,Task 11 追加段落)                         │
└────────────────────────────────────────────────────────────┘
```

---

## 4. Task 列表

### Task 0 — 清理 worktree 既有未提交變動

- **目標:** 把跟本計畫無關的 22 D / 3 M / 4 ?? 變動歸位(stash 或 commit),確保新分支從乾淨基線開始。
- **影響檔案數:** 約 30 個既有變動 + 2 個新 commit。
- **產出:** 分支 `chore/ci-align-team-template`、stash×2、commit×2(刪除 AI 殘留、提交 CLAUDE.md + docs/superpower/)。
- **Why first:** 後續 Task 全部需要乾淨 worktree;若髒狀態帶進來,renormalize 和 commit 都會混雜。
- **詳細實作:** Spec §Task 0

### Task 1 — 建立 `.gitattributes` + 行尾正規化

- **目標:** 確立全域 LF 規範,把既有 CRLF 檔正規化。
- **新增檔案:** `.gitattributes`
- **可能風險:** `git add --renormalize .` 影響範圍未知,先 dry-run。
- **詳細實作:** Spec §Task 1

### Task 2 — 引入 line-ending CI 腳本

- **目標:** 把 R2 的規範自動化執行。
- **新增檔案:** `.github/scripts/check-line-endings.mjs`
- **依賴:** Task 1 完成
- **詳細實作:** Spec §Task 2

### Task 3 — 重寫 `docker-ci.yml` 對齊團隊結構

- **目標:** concurrency + 最小 permissions + basics job + 移除重複 jobs(`security-scan`、`shell-test`)。
- **修改檔案:** `.github/workflows/docker-ci.yml`
- **重要決策:** 不全盤抄團隊 `ci.yml`(因本 repo 無 frontend / backend / flutter / e2e),只抄 basics 概念。
- **詳細實作:** Spec §Task 3

### Task 4 — `docker-publish.yml` 補 permissions / concurrency + 修 push id bug

- **目標:** 加最小 permissions 並於 publish job 內覆寫寫入權限;修補 `steps.push.outputs.digest` 引用缺失的 `id: push`。
- **修改檔案:** `.github/workflows/docker-publish.yml`
- **詳細實作:** Spec §Task 4

### Task 5 — 其餘 3 workflow 補 concurrency + permissions

- **目標:** `script-test.yml` / `security-scan.yml` / `proxmox-k8s-ci.yml` 都加 concurrency,缺 permissions 的補上,checkout 改 @v4。
- **詳細實作:** Spec §Task 5

### Task 6 — PR Labeler

- **目標:** 加自動標籤(docker / scripts / nginx / database / proxmox / ci-cd / documentation / dependencies / config)。
- **新增檔案:** `.github/workflows/pr-labeler.yml`、`.github/labeler.yml`
- **重要決策:** Labels 改用 docker-operation 客製分類,不抄團隊的 vue / dart / cs。
- **詳細實作:** Spec §Task 6

### Task 7 — 對齊 `dependabot.yml`

- **目標:** 用團隊格式(timezone / labels / open-pull-requests-limit / commit-message scope)。
- **修改檔案:** `.github/dependabot.yml`
- **動態調整:** 根目錄無 Dockerfile,只配置 `nginx1.29.3-docker` 子目錄,其他 Dockerfile 子目錄按需擴充。
- **詳細實作:** Spec §Task 7

### Task 8 — PR template(裁減版)

- **目標:** 用團隊範本但刪掉 UI / API / DB migration 段落(本 repo 無此需求)。
- **新增檔案:** `.github/PULL_REQUEST_TEMPLATE.md`
- **詳細實作:** Spec §Task 8

### Task 9 — Issue templates

- **目標:** bug / feature / config 三檔;bug 環境欄位改為 Docker 版本。
- **新增檔案:** `.github/ISSUE_TEMPLATE/{bug_report,feature_request,config}.yml`
- **TODO 留 user:** `config.yml` 內團隊頻道 URL 與資安通報信箱。
- **詳細實作:** Spec §Task 9

### Task 10 — CODEOWNERS 佔位

- **目標:** 預設擁有者 + Docker / `.github/` / `docs/` 區段。
- **新增檔案:** `.github/CODEOWNERS`
- **TODO 留 user:** `@TW199501` 個人佔位待替換為團隊。
- **詳細實作:** Spec §Task 10

### Task 11 — Compose 命名規範文件化 + advisory CI

- **目標:** 規範條文寫入 `docs/conventions/compose-naming.md`、CLAUDE.md 追加段落、CI advisory 檢查(warn-only,不擋 PR)。
- **新增檔案:** `docs/conventions/compose-naming.md`
- **修改檔案:** `CLAUDE.md`、`.github/workflows/docker-ci.yml`
- **重要決策:** **不**自動 rename 6 個違規檔(會破壞既有 scripts/docs/CI 引用);先列違規清單供後續決定。
- **詳細實作:** Spec §Task 11

### Task 12 — `.env` / secrets 規範 + CI 強制阻擋

- **目標:** 補齊 `.gitignore` / `.dockerignore` 規則對齊團隊;在 docker-ci.yml basics job 加雙重阻擋(整 repo + PR diff);修 typo `gitea/.env.exampke`。
- **修改檔案:** `.gitignore`、`.dockerignore`、`.github/workflows/docker-ci.yml`、rename `gitea/.env.exampke` → `gitea/.env.example`
- **重要決策:** 機密外洩是 zero-tolerance,**不**用 `continue-on-error`。
- **詳細實作:** Spec §Task 12

### Task 13 — 全域驗證 + 推送

- **目標:** 列 commit 清單、全 YAML 驗證、line-ending 終驗、push 分支(等 user 同意)。
- **詳細實作:** Spec §Task 13

---

## 5. 執行節奏選項

### A. 一氣呵成(本 session 內全跑)
- **優點:** 一份 PR 含完整對齊;commit 歷史乾淨;user 可一次性 review。
- **缺點:** 14 個 Task,中途若卡關需切回問問題,context 累積較重。

### B. 分批(每 N 個 Task 開一個 PR)
- **優點:** 每個 PR 體積小、review 快。
- **缺點:** 多個 PR 之間有依賴(Task 1 → Task 2 → Task 3),review 順序綁定,反而拖慢。

**建議:A 漸進派,單 session 完成、單 PR review。**

---

## 6. 取捨點(Decision Points 給 user)

| # | 決策 | 選項 | 推薦 | 為什麼 |
| --- | --- | --- | --- | --- |
| D1 | Task 0 中 `123.md` | 刪 / stash / 移到別處 | **stash** | 1 byte scratch,先觀察 |
| D2 | `集運數據集/` 13 個 .md | 接受刪除進 commit / 還原 / 移到外部 repo | **接受刪除**(user 已從 worktree 刪除) | 業務無關 |
| D3 | `.windsurf/`、`.kilocode/`、`.mcp/`、`.codebuddy/` 殘留 | 接受刪除 / 還原 | **接受刪除** | AI 工具殘留,本 repo 用 Claude Code |
| D4 | Dependabot Docker 子目錄 | 只配 `nginx1.29.3-docker` / 掃描全 repo 自動加 | **只配 nginx1.29.3-docker** | 其他子目錄多用官方 image,無自建 Dockerfile |
| D5 | Compose 命名 advisory 何時轉強制? | 一次轉強制 / 漸進改名後再轉 | **漸進改名後**(`continue-on-error: true`) | 6 個違規檔需先逐一處理 reference |
| D6 | `.env` 阻擋是否回溯 git history? | 用 `git filter-repo` rewrite / 只擋未來 | **只擋未來**(若盤點無洩漏) | 已盤點:無 .env 進 git,不需 rewrite |
| D7 | CODEOWNERS 擁有者 | 個人 / 團隊 group | **個人佔位 @TW199501**,user 後續改 | 本 repo 目前無團隊組織 |

---

## 7. 風險清單

| 風險 | 影響 | 緩解策略 |
| --- | --- | --- |
| `git add --renormalize .` 動到大量檔案 | commit 巨大、diff review 困難 | Task 1 先 dry-run,若 >200 行暫停回報 |
| `actions/checkout@v6` 改 @v4 後行為差異 | CI 突然失敗 | v4 是 stable 版,@v6 本就不存在(誤值) |
| Conventional Commits 強制後既有 PR 標題不符 | PR 被擋 | 只在 PR 到 main 觸發;commit 歷史不檢查 |
| `.env` 阻擋誤殺 `.env.example` | basics job 失敗擋 PR | Regex 已加 `grep -vE '(^|/)\.env\.example$'` 例外 |
| Dependabot 動到 base image 引發 build 失敗 | 自動 PR 紅燈 | dependabot 配 `open-pull-requests-limit: 3`,人工合併 |
| Compose 命名 advisory 一開始 6 個 warning | 雜訊干擾 | 用 `::warning::`(GitHub Annotations),不擋 CI |
| Line-ending CI 在 user 用 Windows 編輯後失敗 | PR 紅燈 | `.gitattributes` `eol=lf` 會在 checkout 時轉,user 本機 LF |

---

## 8. 成功指標(Definition of Done)

- ✅ 新分支 `chore/ci-align-team-template`,基線乾淨,共 ~15 個 commit(Task 0 兩個 + Task 1–13 各一個)
- ✅ 全部 `.github` 下 YAML 通過 `yaml.safe_load`
- ✅ `node .github/scripts/check-line-endings.mjs` 本機通過
- ✅ `git ls-files | grep .env`(非 .example)無輸出
- ✅ `docker-ci.yml` 內 shell-test 與 security-scan job 已移除,功能改由獨立 workflow 承擔
- ✅ 所有 workflow 含 `concurrency` 區塊,且 `permissions` 最小化
- ✅ PR template / Issue templates / CODEOWNERS 已生效(在 GitHub UI 看得到)
- ✅ Dependabot PR 開始按 `chore(ci)` / `chore(docker)` scope 命名

---

## 9. 不在範圍(Out of Scope)

- 引入 `release.yml`(本 repo 用 `Dockerfile/bump-version.sh` 自有版本管理)
- 引入 frontend / backend / flutter / e2e job(本 repo 無對應原始碼)
- `check-test-colocation.mjs`(本 repo 無 src/ 與單元測試 colocate 結構)
- 重寫 `docker-publish.yml` 推送邏輯(已運作,只補 permissions / id bug)
- mass rename 6 個違規 compose 檔(本 Plan 只列違規,改名另案)
- `.env` history rewrite(已盤點無洩漏,不需破壞性操作)
- 引入 SECURITY.md / CHANGELOG.md / CONTRIBUTING.md(SECURITY.md 已存在,其他屬另一輪治理)
- 啟用 GitHub repo settings 級的 secret_scanning(屬 UI 設定,需 user 在 GitHub 開)

---

## 10. Follow-Up(完成後可再立的 Plan)

1. **Compose mass rename** — 為 6 個違規檔逐一規劃改名 PR,同步更新所有 reference
2. **CI advisory 轉強制** — 待 mass rename 完成後,把 Task 11 的 `continue-on-error` 拔掉
3. **`Dockerfile/` 子目錄 Dependabot 擴充** — 盤點所有自建 Dockerfile 子目錄,逐一加 docker ecosystem
4. **CODEOWNERS 從個人改團隊** — 等 GitHub 組織 / 團隊 group 建好
5. **Issue template 補充** — `config.yml` 內團隊頻道 URL 與資安通報信箱
6. **SECURITY.md 對齊團隊** — 現有版本是舊的,可參考團隊 `SECURITY.md` 重寫
7. **secret_scanning 啟用** — repo settings → Security → Secret scanning

---

## 11. 取得 approve 前的待回答問題

1. **Task 0 git 清理:** 確認 D2 / D3 接受刪除(user 已從 worktree 刪檔,只是還沒 commit)?
2. **Task 1 dry-run:** renormalize 影響檔案若超過 200 行,要不要暫停回報、或直接接受?
3. **Task 11 violator 報告:** 違規檔 reference 報告寫進 spec 還是另開檔?目前計畫是寫進 `docs/conventions/compose-naming.md` 表格的「Rename 影響」欄。
4. **執行節奏:** 確認選 A 一氣呵成?
