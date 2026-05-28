# .env 命名規範 + Bootstrap 工具鏈 Plan — 策略層

> **類型:** Plan(策略層)
> **建立日期:** 2026-05-28
> **對應 Spec:** [`../spec/2026-05-28-env-conventions.md`](../spec/2026-05-28-env-conventions.md)
> **基底分支:** `chore/ci-align-team-template`(本 plan 依賴前一 plan 建好的 docker-ci.yml basics job)
> **狀態:** Draft

---

## 1. 動機與背景

本 repo 有 11 個 `.env.example`,**6 種不同寫法**,沒有規範:

| 寫法 | 範例 | 出處 |
|---|---|---|
| 英文佔位 | `your_secure_password_here` | DB/POSTGRES |
| 看似真密碼 | `YourStrong!Password123` | DB/SQLServer ⚠️ |
| 重複變數名 | `REDIS_PASSWORD=REDIS_PASSWORD` | DB/redis、openwebui |
| Shell 變數展開(無效) | `SERVER_SECRET=${SERVER_SECRET}` | electerm-web |
| 中文模板 | `your_admin_password # 管理員密碼` | answer |
| **真實密碼字串** 🚨 | `'Elf23887711'` | gitea/.env.example line 31 |

**實證:測試框架根本不讀 `.env.example`**(`docker-compose config --quiet` 預設讀 `.env`,沒檔時 `${VAR}` 變空字串但 exit 0)。意味著 `.env.example` 跟 compose.yml 的變數可能完全不同步,**沒人會發現**直到實際部署。

**核心信念:**
- `.env.example` 是「給 bootstrap 腳本讀的源頭」,不是給人手抄的範例
- 密碼類用真實 shell `$(openssl rand ...)` 自動生成,不寫死也不寫佔位
- Bootstrap 跑一次 → 真實值的 `.env`(進 `.gitignore`)→ docker-compose 才讀得到

---

## 2. 責任邊界

| # | 需求 | 影響層 | 風險 |
|---|---|---|---|
| R1 | `.env.example` 統一語法規範 | 文件 + 11 個既有 example 改寫 | 改錯導致 bootstrap 生成壞值 |
| R2 | Bootstrap 腳本(完整版) | `scripts/env/` 新工具 + 測試 | 跨平台(Linux/macOS/Windows Git Bash) |
| R3 | CI 驗證:語法白名單 | docker-ci.yml basics job 新 step | false positive 擋 PR |
| R4 | CI 驗證:example ↔ compose 變數同步 | docker-ci.yml basics job 新 step | false positive |
| R5 | gitea/.env.example:31 真密碼處理 | 緊急 revoke,可能 history rewrite | 視 user 確認密碼真實性 |

**相依鏈:**
- R1(規範文件 + example 改寫)必須最先
- R2(bootstrap)依賴 R1 的語法定義
- R3 / R4(CI 驗證)依賴 R1 的規範
- R5 獨立,但建議在 R1 之前處理(零容忍)

---

## 3. 總體架構

```
源頭(進 git):                           工具:                     產出(不進 git):
.env.example  ─────────────────────────> bootstrap-env.sh ──────> .env
  ├─ KEY=value                              ├─ 白名單檢查           └─> docker-compose up -d
  ├─ KEY=$(openssl rand -base64 32)         ├─ 隨機值執行
  ├─ KEY=                  # 空 = 必填      ├─ 空值互動 prompt
  └─ # 區塊註解                              ├─ skip-if-exists
                                            ├─ --force 覆寫
                                            └─ --dry-run 預覽

驗證層(CI):
.github/workflows/docker-ci.yml > basics job
  ├─ check-env-syntax.sh:.env.example 內 $(...) 必須在白名單
  └─ check-env-coverage.sh:compose.yml 用到的 ${VAR} 必須在 .env.example 有對應行
```

---

## 4. Task 列表

### Task 0 — 緊急處理 gitea/.env.example:31 疑似真實密碼

- **目標:** 確認 `'Elf23887711'` 真假;若真,revoke + 評估 history rewrite。
- **詳細實作:** Spec §Task 0

### Task 1 — `.env` 命名規範文件

- **目標:** 寫 `docs/conventions/env-naming.md`,定義 5 條語法規則 + 白名單命令清單 + 範例。
- **新增檔案:** `docs/conventions/env-naming.md`
- **修改檔案:** `CLAUDE.md`(加段落引用本規範)
- **詳細實作:** Spec §Task 1

### Task 2 — Bootstrap 腳本 `scripts/env/bootstrap-env.sh`(完整版)

- **目標:** ~150 行 Bash,功能含:白名單 / skip-if-exists / `--force` / `--dry-run` / 空值互動 prompt / 顏色輸出 / 跨平台。
- **新增檔案:** `scripts/env/bootstrap-env.sh`、`scripts/env/lib/whitelist.sh`、`scripts/env/README.md`
- **詳細實作:** Spec §Task 2

### Task 3 — Bootstrap 腳本測試

- **目標:** Bats 測試覆蓋核心情境(白名單擋 / 隨機值生成 / skip / force / dry-run / 空值 prompt)。
- **新增檔案:** `tests/env/test_bootstrap.bats`
- **修改檔案:** `tests/run_all_tests.sh` 加 hook
- **詳細實作:** Spec §Task 3

### Task 4 — CI step:syntax 白名單檢查

- **目標:** `scripts/env/check-env-syntax.sh` + docker-ci.yml basics job 加 step。
- **新增檔案:** `scripts/env/check-env-syntax.sh`
- **修改檔案:** `.github/workflows/docker-ci.yml`
- **詳細實作:** Spec §Task 4

### Task 5 — CI step:example ↔ compose 變數同步檢查

- **目標:** `scripts/env/check-env-coverage.sh` + docker-ci.yml basics job 加 step(advisory,warn-only)。
- **新增檔案:** `scripts/env/check-env-coverage.sh`
- **修改檔案:** `.github/workflows/docker-ci.yml`
- **詳細實作:** Spec §Task 5

### Task 6 — 改寫 11 個既有 `.env.example`

- **目標:** 全部對齊 Task 1 規範。密碼類改 `$(openssl rand -base64 32)`,必填改空值,加註解。
- **修改檔案:** 11 個 `.env.example`
- **詳細實作:** Spec §Task 6

### Task 7 — 全域驗證 + 推送

- **目標:** 跑 bootstrap 對 11 個 stack 各跑一次驗證能產出 `.env`;CI step 本機通過;推 PR。
- **詳細實作:** Spec §Task 7

---

## 5. 執行節奏

**選擇:一氣呵成(本 session 完成 Task 0-7)**
- 一份 PR 含完整對齊
- 8 個 task,顆粒度跟前一 plan 一致

---

## 6. 取捨點

| # | 決策 | 選項 | 推薦 | 理由 |
|---|---|---|---|---|
| D1 | bootstrap 腳本語言 | Bash / Python | **Bash** | 依賴最少;跨平台靠 Git Bash;本 repo 已大量 Bash |
| D2 | 白名單實作位置 | 內嵌 / 獨立 lib | **獨立 `lib/whitelist.sh`** | 方便 CI step 與 bootstrap 共用 |
| D3 | 白名單命令清單 | 嚴格(只 openssl/uuidgen) / 寬鬆 | **嚴格** | `.env.example` 進 git 是 attack surface,寬鬆會被植入 `$(curl evil)` |
| D4 | 空值處理 | 互動 prompt / 失敗 / 隨機 | **互動 prompt**(CI 環境改 `--non-interactive` 失敗) | 對人友善 + CI 不卡 |
| D5 | 既有 `.env` 處理 | skip / backup / overwrite | **skip-if-exists**,需 `--force` 強制 | 不誤殺現役密碼 |
| D6 | CI Task 5(覆蓋率)強度 | 強制 / advisory | **advisory**(warn-only) | 現存 11 個 example 改完後再轉強制 |
| D7 | `Elf23887711` 處理 | revoke+rewrite / 只 revoke / 假密碼略過 | **問 user**(Task 0) | 視真假決定 |

---

## 7. 風險清單

| 風險 | 影響 | 緩解 |
|---|---|---|
| Bootstrap source 含 `$(curl evil)` | RCE | 白名單檢查(R3) + 在 source 前先掃語法 |
| 含空格的值未引號被 bash source 炸 | bootstrap 失敗 | 規範強制雙引號;bootstrap 在 source 前 validate |
| 跨平台 `openssl` 不存在 | bootstrap 失敗 | 啟動時檢查工具鏈,缺則明確報錯 |
| 既有 `.env` 被覆蓋 | 現役密碼遺失 | skip-if-exists 預設;`--force` 才覆蓋且 backup |
| CI 對既有違規檔誤殺 PR | 開發者罵聲 | Task 4 強制,Task 5 advisory;Task 6 完成才確保不誤殺 |
| `Elf23887711` 已被外部使用 | 密碼洩漏不可逆 | Task 0 確認 + revoke |

---

## 8. 成功指標(Definition of Done)

- ✅ 11 個 `.env.example` 全部符合 Task 1 規範
- ✅ `bootstrap-env.sh DB/POSTGRES` 跑完產出有效 `.env`
- ✅ `bootstrap-env.sh` 對含 `$(curl ...)` 的 example 拒絕執行
- ✅ `bootstrap-env.sh` 對已存在 `.env` 默認 skip
- ✅ `bootstrap-env.sh --dry-run` 不寫檔
- ✅ Bats 測試全綠
- ✅ CI step 本機跑通(check-env-syntax 強制、check-env-coverage advisory)
- ✅ `gitea/.env.example:31` 問題已解決(視真假決定方案)

---

## 9. 不在範圍(Out of Scope)

- 改 `test_docker_compose.sh` 讓它先 bootstrap 再 config(動測試框架,風險高,另案)
- 對接 Bitwarden / Vault / SOPS(過度工程,本 repo 規模不需要)
- Bootstrap 腳本支援 Windows 原生(只支援 Git Bash;PowerShell 移植另案)
- mass rename 6 個違規 compose 檔(屬前一 Plan 的 follow-up)

---

## 10. Follow-Up

1. Task 5 advisory 轉強制(等 Task 6 改完所有 example 確認無覆蓋率缺口)
2. Bootstrap 對接 macOS / Linux package manager 安裝 openssl 的 hint
3. PowerShell 版 bootstrap(若 team 有 Windows 純原生需求)
4. `.env` rotation 工具(過期自動重產)

---

## 11. 取得 approve 前的待回答問題

1. **`gitea/.env.example:31` 那個 `Elf23887711`** — 真實密碼還是 fake?(影響 Task 0 走向)
2. **白名單範圍**:預計只放 `openssl` / `uuidgen` / `date` / `hostname` / `cat` / `tr`,可加?
3. **互動 prompt 風格** — 簡單(`Enter ADMIN_EMAIL:`)還是含說明(`Enter ADMIN_EMAIL (will be used for admin login):`)
4. **Bats 是否要在 CI 跑?**(本機 Bats 已是 tests/ 框架的一部分,但 docker-ci.yml 沒包進來)
