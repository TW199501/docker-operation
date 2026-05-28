---
name: Memory 一律存專案目錄,不放全域
description: 團隊約定:agent 記憶必須寫進專案內 docs/superpower/memory/,不要寫到使用者全域 .claude 目錄
type: feedback
---

**規則:** Agent 記憶(無論是 user / feedback / project / reference 類型)**一律存放在專案內** `docs/superpower/memory/`,**禁止**寫到全域路徑(如 `C:\Users\<user>\.claude\projects\...\memory\`)。

**檔案組織:**
- `docs/superpower/memory/MEMORY.md` — 索引,每條記憶一行 `- [標題](file.md) — 一句話描述`
- `docs/superpower/memory/<type>_<topic>.md` — 個別記憶檔,含 frontmatter (name / description / type)

**目錄命名對齊團隊:**
- 用單數 `superpower`(對齊 `team-project-template/docs/superpower/`),不用複數 `superpowers`
- plan 子目錄用 `plan`(單數)、memory 子目錄用 `memory`、spec 子目錄用 `spec`

**Why:** 團隊約定 — 記憶必須跟著 repo 走,新成員 clone 就有完整脈絡;放全域會綁定特定機器/帳號,協作斷裂。團隊範本 `e:\source\team-project-template\docs\superpower\` 已有 plan/spec 子目錄,memory 對齊放在同層。

**How to apply:** 任何時候要 save memory,目標路徑都是 `<project-root>/docs/superpower/memory/`。CLAUDE.md 系統提示若指向全域 memory 路徑,以本規範為準覆蓋之。
