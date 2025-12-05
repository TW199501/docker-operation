# HAPPY AI TODO TREE

## 目的

給 AI 與使用者共用的一份簡易 TODO Tree 模板，用來記錄「已選定的方案」與「後續實作步驟」，避免在對話裡重複長篇說明。

## 標記約定

- `TODO`一般待辦事項（可以有多個步驟）。
- `NOTE`用來簡短描述「方案」或設計決策，例如：

  ```text
  // NOTE 方案A: modules.conf 改名 default.modules.main.conf
  // NOTE 方案B: modules.conf 放在 geoip 目錄（不建議）
  ```

- `[ ]` / `[x]`
  對應 VS Code todo-tree 的透明 / 藍色標記：

  ```text
  // [ ] 實作: 套用方案A，修改 nginx.conf include 路徑
  // [x] 已完成: 重跑 nginx -t 並通過
  ```

> 顏色設定已在 `.vscode/settings.json` 裡使用 `"rgba(128,128,128,0.75)"` 與 `"transparent"` 等，不需在這裡重複設定。

## 使用流程模板

1. **提出方案**使用者說「提出方案寫入 TODO TREE」時：

   - AI 選出 1–3 個可行方案。
   - 只在程式碼或文件中寫入極短的 `NOTE` 方案說明，不在對話中長篇展開。
2. **記錄待辦（TODO + [ ]）**對每個決定要做的實作，寫一行任務，例如：

   ```text
   // [ ] TODO: 重構 nginx.conf，導入 main.conf 包裝結構
   ```

3. **實作時更新狀態**每完成一件事：

   ```text
   // [x] TODO: 重構 nginx.conf，導入 main.conf 包裝結構
   ```

4. **對話輸出控制**

   - 對話中只回「哪一個 TODO 正在做」與「必要指令」，盡量少於 100 字。
   - 詳細背景或替代方案，只寫在 `NOTE` 註解裡，不在對話反覆重講。

## 範例結構（供 AI 參考）

```text
# 模組載入與 nginx-ui 相容性

// NOTE 方案A: modules.conf 改名 default.modules.main.conf，避免 webui BUG
// NOTE 方案B: 保持 modules.conf 檔名，但移出 webui 掃描範圍
// [X] TODO: 選定方案A，修改檔名與 nginx.conf include 路徑

# Nginx 主設定分層

// NOTE: nginx.conf 只做薄殼，實際邏輯放 main.conf，降低 webui 破壞風險
// [] TODO: 建立 main.conf，搬移現有 http/server/upstream 設定
// [] TODO: 在 Docker 映像 seed 階段同步 main.conf

# 模組啟用策略

// NOTE: 初次部署時所有 load_module 先註解，逐條開啟 + nginx -t 驗證
// [x] TODO: 在 default.modules.main.conf 加上註解版本，寫入啟用流程

# Compose 分離與 nginx-ui 整合

// NOTE: haproxy+nginx 作為「流量 stack」，nginx-ui 作為「管理 stack」，用兩份 compose，但共用同一套 /etc/nginx 與 docker.sock
// [] TODO: 調整 haproxy+nginx compose，把 Nginx 的 /etc/nginx 等掛點統一到 /opt/stacks/... 路徑（供 nginx-ui 共用）
// [] TODO: 調整 nginx-ui-compose.yml，把左側 volume 路徑改成與 haproxy+nginx 同一套主機目錄
// [] TODO: 文件化兩個 compose 的啟動/停止指令與 debug 流程
```

> AI 在閱讀本檔時，只需視它為「任務與方案的索引」，實際實作細節以程式碼中的 `NOTE` / `TODO` / `[ ]` / `[x]` 為準。
