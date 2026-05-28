# Docker Compose 檔案命名規範

> **規範狀態:** Advisory(2026-05-28 起)
> CI 會以 `::warning::` 提示違規檔,但**不擋 PR**。
> 待 6 個既有違規檔逐一改名 + 同步更新 reference 後,本規範轉強制。

---

## 1. 規則

1. **目錄名表達專案** — 子目錄(如 `nginx1.29.3-docker/`、`DB/POSTGRES/`)本身即為專案識別,**compose 檔名內禁止再重複專案名**。
2. **預設**:`docker-compose.yml`。
3. **變體**:用**點(`.`)**分隔變體標記,不用 dash:
   - 環境:`docker-compose.dev.yml` / `docker-compose.test.yml` / `docker-compose.staging.yml` / `docker-compose.prod.yml`
   - 用途:`docker-compose.build.yml` / `docker-compose.backup.yml` / `docker-compose.ui.yml`
4. **禁止**:
   - `compose-<x>.yml` — 把 `compose` 放前面
   - `<x>-compose.yml` — 把 `compose` 放後面
   - `docker-compose-<x>.yml` — 用 dash 而非 dot
   - 檔名內重複目錄/專案名(如 `gitea/docker-compose-gitea.yml`)

---

## 2. 為什麼

- **檔名一致** → CI 工具、批次腳本可用統一 glob(`**/docker-compose*.yml`)取到所有 compose 檔。
- **點分隔** → 與 Docker 官方 multi-file pattern(`-f docker-compose.yml -f docker-compose.prod.yml`)對齊,自然支援 layered override。
- **目錄識別專案** → 避免 `gitea/docker-compose-gitea.yml` 之類的冗餘。

---

## 3. 規範依據

- 團隊範本 [`team-project-template/docker/README.md` §三](file:///E:/source/team-project-template/docker/README.md)「命名規範」
- 本 repo `CLAUDE.md`「Compose 檔命名規範」段落
- 與 `.gitattributes` + `.github/scripts/check-line-endings.mjs` 同屬團隊統一基線

---

## 4. 現存違規清單(2026-05-28 盤點)

| # | 違規路徑 | 建議改名 | 影響 reference 數 |
|---|---|---|---|
| 1 | `DB/POSTGRES/pgbackup-compose.yml` | `DB/POSTGRES/docker-compose.backup.yml` | 0(孤兒檔) |
| 2 | `gitea/docker-compose-pg.yml` | `gitea/docker-compose.pg.yml` | 0(孤兒檔) |
| 3 | `gitea/runner/docker-compose-mssql.yml` | `gitea/runner/docker-compose.mssql.yml` | 0(孤兒檔) |
| 4 | `nginx/compose-nginx-ui.yml` | `nginx/docker-compose.ui.yml` | 0(孤兒檔) |
| 5 | `nginx1.29.3-docker/nginx-ui-compose.yml` | `nginx1.29.3-docker/docker-compose.ui.yml` | **7**(README.md / README.en.md / docs/configuration.md / docs/deployment-guide.md) |
| 6 | `ollama/docker-compose-6card.yml` | `ollama/docker-compose.6card.yml` | 0(孤兒檔) |

**改名 SOP**:
1. `grep -rn <舊檔名> .` 確認影響範圍
2. `git mv 舊檔 新檔`
3. 逐一同步更新 docs / shell scripts / CI workflows 中所有引用
4. 本機跑該 stack 的 `docker-compose -f <新檔名> config --quiet`
5. PR 提交

---

## 5. 何時轉強制

待 6 個違規檔全部處理完(改名 + 文件同步),在 `.github/workflows/docker-ci.yml` 的 `basics` job 的 compose naming 檢查 step 內:

```diff
-      - name: Check docker-compose file naming convention (advisory)
-        continue-on-error: true
+      - name: Check docker-compose file naming convention
+        # 不再 continue-on-error → 違規即擋 PR
```

並把 `echo "::warning::..."` 改為 `echo "::error::..." && exit 1`。
