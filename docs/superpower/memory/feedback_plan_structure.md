---
name: 計畫結構固定用 Plan → Task
description: 撰寫實作計畫時,頂層用「Plan」、子單元一律用「Task N」,每個 Task 結尾以一次 git commit 收斂
type: feedback
---

撰寫實作計畫(superpowers:writing-plans 或一般 plan 文件)時,**一律用 Plan → Task** 結構:

- 頂層文件 = 一份 Plan
- 子單元 = Task 1 / Task 2 / Task 3 ...(**不**用 Phase / Stage / Step 當子單元名)
- 每個 Task 內含多個 `- [ ] Step N` 小步驟
- **每個 Task 結尾必須以一次 `git commit` 收斂**(顆粒度:一個邏輯單元 = 一個 commit)

**Why:** 使用者團隊已採用此結構(原團隊用語為 Phase,2026-05-28 對齊改用 Task),命名統一可避免溝通混淆;每 Task 一個 commit 便於 review 與回退。

**How to apply:** 不論用 superpowers:writing-plans 還是直接寫 markdown 計畫,標題都用 `## Task N: ...`、絕不要用 `## Phase N` 或 `## Stage N`。團隊範本後續若仍出現 Phase 字樣,以 Task 為準。
