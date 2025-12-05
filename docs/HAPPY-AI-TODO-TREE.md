# HAProxy Docker 構建 TODO

## 目的

檢查和優化 HAProxy 3.3.0 Docker 構建配置

## 當前狀態分析

### ✅ 配置正確項目

- 版本設定：HAPROXY_VERSION 3.3.0
- URL 和 SHA256 校驗值完整
- 編譯參數正確（LUA, PCRE2, OpenSSL, PROMEX）
- 支援 debian 和 alpine 兩個版本
- docker-entrypoint.sh 配置正確

### [ ] 可能需要調整的項目

// NOTE 方案A: 保持當前 3.3.0 版本格式（推薦）
// NOTE 方案B: 如需修改版本號格式，統一更新所有相關檔案

// [x] TODO: 修復缺失的 COPY haproxy.cfg 指令（debian + alpine）
// [ ] TODO: 測試構建 debian 版本
// [ ] TODO: 測試構建 alpine 版本
// [ ] TODO: 驗證 haproxy -v 輸出版本正確
// [ ] TODO: 檢查 Docker 映像大小是否合理
