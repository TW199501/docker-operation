# PR Description — chore/ci-align-team-template

> **複製從 `## Summary` 開始的內容貼到 GitHub PR 表單**

---

## Summary

把 `E:\source\team-project-template\.github` 已統一的工作流規範套用到本 repo,涵蓋 14 個 Task:

- workflows 加 `concurrency` + 最小 `permissions` + `actions/checkout@v6` → `@v4`
- 移除 `docker-ci.yml` 內與 `security-scan.yml` / `script-test.yml` 重複的 jobs
- 修補 `docker-publish.yml` 缺 `id: push` 的隱性 bug(attest-build-provenance 引用空字串)
- 新增:PR template / Issue templates / CODEOWNERS / labeler / dependabot 對齊團隊格式
- 行尾規範:`.gitattributes` + `check-line-endings.mjs` CI 強制
- compose 命名規範(advisory)
- `.env` / secrets 規範(CI 強制阻擋)
- 修 typo:`gitea/.env.exampke` → `gitea/.env.example`

> 詳細策略 / 設計動機見 [`docs/superpower/plan/2026-05-28-cicd-team-conventions.md`](docs/superpower/plan/2026-05-28-cicd-team-conventions.md)
> 實作細節見 [`docs/superpower/spec/2026-05-28-cicd-team-conventions.md`](docs/superpower/spec/2026-05-28-cicd-team-conventions.md)

---

## Commits(14 個 Task,各自一個 commit)

| # | Commit | 內容 |
|---|---|---|
| Task 0 (1/2) | `62fa373` | 刪除 stale AI 工具殘留 + 業務無關 `集運數據集/` |
| Task 0 (2/2) | `b01805d` | 加 `CLAUDE.md` + `docs/superpower/{plan,spec,memory}` 基線 |
| Task 1 | `c8b9212` | `.gitattributes` + 行尾正規化(全域 LF,Windows 批次檔 CRLF) |
| Task 2 | `a9529f7` | `.github/scripts/check-line-endings.mjs`(CI 強制) |
| Task 3 | `1ecdcbf` | 重寫 `docker-ci.yml`:加 basics job、移除重複 jobs |
| Task 4 | `6dc6bad` | `docker-publish.yml`:最小 permissions + 修 `id: push` bug |
| Task 5 | `6ac4ed3` | 其餘 3 個 workflow 加 concurrency + permissions |
| Task 6 | `c820aec` | PR Labeler + 客製 `.github/labeler.yml` |
| Task 7 | `5030ecd` | `dependabot.yml` 對齊團隊格式(timezone / scope / labels) |
| Task 8 | `0c87046` | `.github/PULL_REQUEST_TEMPLATE.md` |
| Task 9 | `3ede6ab` | `.github/ISSUE_TEMPLATE/{bug_report,feature_request,config}.yml` |
| Task 10 | `b4f2f99` | `.github/CODEOWNERS` 佔位 |
| Task 11 | `b26b6a3` | Compose 命名規範文件 + advisory CI(warn-only) |
| Task 12 | `826f42c` | `.env` / secrets 規範:`.gitignore` / `.dockerignore` 對齊 + CI 強制 |

---

## Definition of Done

- ✅ 14 個 commit,新分支從乾淨 main 切
- ✅ 全部 `.github` 下 YAML 通過 `yaml.safe_load`
- ✅ `node .github/scripts/check-line-endings.mjs` 本機通過
- ✅ `git ls-files | grep .env`(非 .example)無輸出
- ✅ `docker-ci.yml` 內 shell-test / security-scan job 已移除(改由獨立 workflow 承擔)
- ✅ 所有 workflow 含 `concurrency` 區塊,`permissions` 最小化
- ✅ PR template / Issue templates / CODEOWNERS / Labeler 已就位
- ✅ Dependabot 改用 `chore(ci)` / `chore(docker)` scope 命名

---

## 跟 Dependabot PR 的關係

本 PR 已把 `actions/checkout` 從 `@v6` pin 回 `@v4`。Dependabot PR #14–#18 想升 `docker/*-action` 與 `actions/attest-build-provenance`,這些**沒在本 PR 升**(維持現有 v3/v5/v6/v6/v3),屬另一輪 follow-up。

合 merge 後 Dependabot 下一週掃描會看到新 main,5 個 PR 可能需要 rebase 或手動 close。

---

## 不在範圍(留 follow-up Plan)

- mass rename 6 個違規 compose 檔
- compose naming advisory CI 轉強制
- `Dockerfile/` 子目錄 Dependabot 進一步擴充
- `CODEOWNERS` 個人佔位改團隊 group
- `SECURITY.md` 對齊團隊
- GitHub repo settings 級的 `secret_scanning` 啟用

---

## Test plan

- [ ] CI:`docker-ci.yml` basics job 各 step 全綠(commit lint / line-ending / 大檔 / compose 命名 advisory / .env 阻擋)
- [ ] CI:`script-test.yml` / `security-scan.yml` / `proxmox-k8s-ci.yml` 全綠
- [ ] CI:PR labeler 自動套上 `ci/cd` + `documentation` label
- [ ] PR template 在 GitHub UI 自動展開
- [ ] 本 PR description 沒洩漏任何機密

🤖 Generated with [Claude Code](https://claude.com/claude-code)
