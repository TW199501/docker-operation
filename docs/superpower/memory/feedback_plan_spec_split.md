---
name: 計畫採 Plan + Spec 雙檔對應結構
description: 團隊規範實作計畫拆成 Plan(策略層,Task 列表)與 Spec(實作層,代碼/schema/API)兩份檔,兩者互相對應
type: feedback
---

**團隊規範:** 任何非 trivial 的實作計畫都拆成兩份檔案,Plan 與 Spec 兩兩對應。

## 檔名與位置
- `docs/superpower/plan/YYYY-MM-DD-<feature>.md` — **策略層**
- `docs/superpower/spec/YYYY-MM-DD-<feature>.md` — **實作層**
- 兩檔同名(只差子目錄)、開頭互相 link

## Plan 文件結構(策略層)
1. 動機與背景
2. 責任邊界(需求 → 影響層表格)
3. 總體架構衝擊圖(ASCII / mermaid)
4. **分 Task 執行計畫** — 只列 Task 標題與目標,**不含實作細節**
5. 執行節奏選項(漸進派 / 集中派)
6. 取捨點(Decision Points 給 Tech Lead)
7. 風險清單
8. 成功指標(Definition of Done)
9. 不在範圍(Out of Scope)
10. Follow-Up(完成後可再立的)
11. 取得 approve 前的待回答問題

## Spec 文件結構(實作層)
1. 變更總覽(新建/修改/移除檔案數量表)
2. 各 component 詳細實作:
   - DB schema 變更 + migration SQL
   - 新增/修改 API endpoint 的 request/response + 內部實作代碼
   - 前端 component 結構 / CSS / JS 代碼
   - 規範文件變更
   - Pre-commit / CI script 代碼
3. 章節按 component / 檔案組織,**不**按 Task 重複組織 — 但每段標明對應 Plan 的哪個 Task

## 兩者對應關係
- Plan 第 4 章 Task N → Spec 內標明「對應 Plan Task N」的多個章節
- 一個 Task 可能對應 Spec 多個章節(如「Task 3 新增 history API」對應 Spec 的「DB schema」+「API endpoint」+「前端 history panel」)
- Spec 標題若有對應 Task,於章節開頭註明 `> 對應 Plan: Task N`

## 例外:trivial 任務
單檔修改、純文字、純 config 調整不需拆 Plan + Spec,直接 commit 即可。
但只要涉及 3 個檔以上、或有架構決策、或牽涉多個元件,**必須**拆。

**Why:** 團隊範本 `e:\source\team-project-template\docs\superpower\{plan,spec}/` 已示範此格式;Plan 用來向 Tech Lead 取得 approve(只看策略),Spec 用來實作(只看代碼)。混在一起的計畫文件 review 時 reviewer 抓不到重點。

**How to apply:**
- 寫計畫前先準備兩個檔案 path(同名,差子目錄)
- Plan 不允許出現多行代碼塊;Spec 不允許出現 DoD / 風險 / 取捨點
- 兩檔的「對應」link 用相對路徑(`../spec/...` / `../plan/...`)
- 與「Plan → Task」記憶共同生效:Plan 內子單元仍叫 Task(不叫 Phase)
