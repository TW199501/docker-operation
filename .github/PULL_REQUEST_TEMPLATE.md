<!--
  PR 標題請遵循 Conventional Commits 格式:
  <type>(<scope>): <subject>

  範例:
    feat(nginx): 加入 GeoIP 過濾規則
    fix(certbot): 修正 cloudflare.ini 路徑判斷
    ci(docker): 升級 actions/checkout 至 v4
    chore(deps): 更新 nginx base image
-->

## 📝 變更摘要

<!-- 1~3 句話說明這個 PR 做了什麼 -->

## 💡 變更動機

<!-- 為什麼要做這個變更?解決什麼問題? -->

## 🏷️ 變更類型

<!-- 勾選符合的項目(可複選) -->

- [ ] `feat`     新功能
- [ ] `fix`      修復 Bug
- [ ] `refactor` 重構(不改變行為)
- [ ] `perf`     效能改善
- [ ] `docs`     文件變更
- [ ] `build`    建置 / 相依套件
- [ ] `ci`       CI 設定
- [ ] `chore`    雜項
- [ ] `revert`   回退

## 🎯 影響範圍

<!-- 哪些 stack / 子目錄受影響? -->

- [ ] Docker (compose / Dockerfile)
- [ ] Shell 腳本 (nginx / proxmox / DB 等)
- [ ] CI/CD (.github/)
- [ ] 文件
- [ ] 其他:

## 🧪 測試方式

<!-- 如何驗證此變更正確?提供本地操作步驟、預期結果 -->

1.
2.
3.

## 🚀 部署注意事項

<!-- 是否需要環境變數、設定、特殊步驟? -->

- [ ] 無
- [ ] 需新增 `.env` 變數:
- [ ] 需更新部署設定:
- [ ] 需重啟特定容器:

## ✅ 提交前檢查清單

- [ ] PR 標題符合 Conventional Commits
- [ ] 本機 `docker-compose config --quiet` 通過
- [ ] 本機 `bash -n` / `shellcheck` 通過
- [ ] 已自我 review diff
- [ ] 沒有夾帶機密資訊(密碼、token、`.env`)
- [ ] 沒有夾帶與本次目的無關的變更
- [ ] 已連結相關 Issue(如有)

## 🔗 相關連結

<!-- Issue、文件、相關 PR -->

- Closes #
- Refs #
