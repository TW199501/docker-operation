# Proxmox Kubernetes 項目 CI/CD 總結

## 已創建的文件

### 主要文檔
- ✅ `ci-cd-setup-guide.md` - 完整的 CI/CD 配置指南
- ✅ `setup-ci-cd.sh` - CI/CD 設置腳本
- ✅ `.github-workflows-ci.yml` - GitHub Actions CI 工作流程

### 配置文件
- ✅ `.markdownlint.json` - Markdown 格式檢查配置
- ✅ `.shellcheckrc` - Shell 腳本檢查配置
- ✅ `.dockerignore` - Docker 忽略文件配置
- ✅ `.pre-commit-config.yaml` - 預提交鉤子配置

## CI/CD 功能概述

### 🔍 **代碼質量檢查**
- Shell 腳本語法檢查 (ShellCheck)
- Markdown 格式檢查 (markdownlint)
- 文件權限檢查
- Makefile 語法驗證

### 🧪 **自動化測試**
- 腳本語法測試
- Make 目標測試
- 文檔結構驗證

### 🔒 **安全掃描**
- 依賴漏洞掃描 (Trivy)
- 密碼洩露檢查 (Gitleaks)
- Shell 腳本安全檢查

### 🚀 **持續部署**
- 自動發佈 (GitHub Releases)
- Docker 鏡像構建和推送
- 依賴自動更新 (Dependabot)

## 使用方法

### 快速設置

1. **運行設置腳本**
   ```bash
   chmod +x setup-ci-cd.sh
   ./setup-ci-cd.sh
   ```

2. **檢查創建的文件**
   ```bash
   ls -la .github/workflows/
   ls -la .*.json .*.yaml .*.rc
   ```

3. **提交到版本控制**
   ```bash
   git add .
   git commit -m "Add CI/CD configuration"
   git push
   ```

### 手動設置（如果需要自定義）

如果您需要修改配置，可以手動創建 `.github/workflows/` 目錄並複製相應文件。

## 工作流程觸發條件

### CI 工作流程 (`ci.yml`)
- **Push**: `main` 和 `develop` 分支
- **Pull Request**: 針對 `main` 分支
- **手動觸發**: 可通過 GitHub Actions 界面手動運行

### 其他工作流程
- **安全掃描**: 每周一自動運行 + 主要分支推送
- **發佈**: 標籤推送 (如 `v1.0.0`)
- **Docker 構建**: Dockerfile 或 docker-compose.yml 變更時

## 監控和維護

### 查看運行狀態
1. 訪問 GitHub 倉庫的 **Actions** 標籤頁
2. 查看最新工作流程運行狀態
3. 檢查失敗的步驟和錯誤信息

### 常見問題處理

#### 1. ShellCheck 錯誤
```bash
# 在腳本中添加忽略註釋
# shellcheck disable=SC2034
variable_name="value"
```

#### 2. Markdown 格式錯誤
調整 `.markdownlint.json` 配置或修復格式問題。

#### 3. 權限問題
```bash
# 確保腳本有執行權限
chmod +x *.sh
git update-index --chmod=+x script.sh
```

#### 4. 依賴更新
Dependabot 會自動創建 PR，定期檢查並合併。

## 安全配置

### GitHub Secrets
在倉庫設置中添加以下 secrets（如果使用對應功能）：
- `DOCKER_USERNAME` - Docker Hub 用戶名
- `DOCKER_PASSWORD` - Docker Hub 密碼

### 代碼所有者
考慮添加 `.github/CODEOWNERS` 文件來定義代碼審查責任。

## 性能優化

### 工作流程優化
- 使用依賴緩存減少構建時間
- 並行運行獨立作業
- 條件執行避免不必要的步驟

### 資源使用
- 使用適當的運行器大小
- 設置作業超時限制
- 合理使用 artifacts

## 擴展功能

### 添加更多檢查
- **單元測試**: 如果項目包含測試
- **性能測試**: 基準測試比較
- **集成測試**: 端到端測試

### 自定義通知
- Slack 或 Discord 通知
- 郵件通知
- 狀態檢查 API

## 故障排除

### 工作流程不運行
1. 檢查 YAML 語法
2. 確認分支名稱匹配
3. 查看 GitHub Actions 用量限制

### 步驟失敗
1. 查看詳細日誌
2. 檢查錯誤信息
3. 驗證本地環境

### 性能問題
1. 檢查緩存使用
2. 優化腳本執行時間
3. 考慮分割大型工作流程

## 總結

這個 CI/CD 配置提供了：
- ✅ **自動化代碼質量檢查**
- ✅ **安全漏洞掃描**
- ✅ **自動化測試**
- ✅ **持續部署能力**
- ✅ **依賴管理**
- ✅ **文檔驗證**

通過這個設置，您的 Proxmox Kubernetes 項目將具備專業級的開發流程，確保代碼質量和安全性，同時提高團隊協作效率。

## 下一步

1. **測試 CI/CD**: 推送代碼觸發工作流程
2. **監控運行**: 檢查 Actions 結果
3. **優化配置**: 根據需要調整規則
4. **添加功能**: 根據項目需求擴展工作流程
