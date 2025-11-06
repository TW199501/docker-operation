## 🛠️ **測試工具總覽**

您的 Docker 專案已經配置了完整的測試工具鏈，以下是可用的測試工具和方法：

### 🔧 **1. 語法檢查工具**

#### **Shell 腳本測試**

```bash
# ShellCheck - 靜態分析工具
shellcheck script.sh

# Bash 語法檢查
bash -n script.sh

# 使用我們的測試框架
cd tests && bash run_all_tests.sh unit
```

#### **Docker Compose 驗證**

```bash
# 語法和配置檢查
docker-compose config

# 安靜模式檢查（只顯示錯誤）
docker-compose config --quiet
```

#### **YAML 語法檢查**

```bash
# 使用 Python 的 yaml 模塊
python3 -c "import yaml; yaml.safe_load(open('docker-compose.yml'))"

# 使用 yq 工具（如果安裝）
yq eval '.' docker-compose.yml
```

### 🧪 **2. 我們的自定義測試框架**

#### **完整測試套件**

```bash
cd tests

# 運行所有測試
bash run_all_tests.sh

# 運行特定測試類型
bash run_all_tests.sh unit        # 單元測試
bash run_all_tests.sh integration # 集成測試
bash run_all_tests.sh e2e         # 端到端測試

# 詳細輸出
bash run_all_tests.sh -v all

# 保存測試報告
bash run_all_tests.sh -o test-report.txt all
```

#### **測試框架特性**

- ✅ **斷言函數**: [assert_equals](cci:1://file:///d:/app/docker-operation/tests/run-tests.sh:40:0-50:1), [assert_contains](cci:1://file:///d:/app/docker-operation/tests/run-tests.sh:52:0-62:1), [assert_file_exists](cci:1://file:///d:/app/docker-operation/tests/run-tests.sh:64:0-73:1)
- ✅ **自動化檢查**: 語法、權限、依賴項
- ✅ **彩色輸出**: 直觀的測試結果顯示
- ✅ **詳細報告**: 測試統計和錯誤追蹤

### 🚀 **3. CI/CD 自動測試**

#### **GitHub Actions 工作流程**

我們的專案已經配置了以下自動測試：

```yaml
# .github/workflows/docker-ci.yml
- Docker 語法檢查 (Hadolint)
- Shell 腳本測試 (ShellCheck)
- Docker Compose 驗證
- 安全掃描 (Trivy)
- 版本一致性檢查
```

#### **測試觸發條件**

- **Push** 到 main/develop 分支
- **Pull Request** 提交
- **修改** 相關文件時自動觸發

### 📊 **4. 專門測試工具**

#### **Docker 相關工具**

```bash
# Hadolint - Dockerfile 檢查
docker run --rm -i hadolint/hadolint < Dockerfile

# Trivy - 安全掃描
trivy config .

# Dive - 鏡像分析
dive image:tag
```

#### **代碼質量工具**

```bash
# ESLint (JavaScript/TypeScript)
npx eslint .

# Prettier (代碼格式化)
npx prettier --check .

# Black (Python)
black --check .
```

### 🔍 **5. 手動測試方法**

#### **基本語法檢查**

```bash
# YAML 語法
python3 -c "
import yaml
try:
    with open('docker-compose.yml') as f:
        yaml.safe_load(f)
    print('✅ YAML 語法正確')
except Exception as e:
    print(f'❌ YAML 語法錯誤: {e}')
"
```

#### **Docker Compose 測試**

```bash
# 檢查服務間依賴
docker-compose config

# 測試網路連通性
docker-compose up -d --scale service_name=0  # 只啟動依賴服務

# 檢查端口衝突
docker-compose ps
```

### 📋 **6. 測試覆蓋範圍**

| 測試類型             | 工具                  | 檢查內容        |
| -------------------- | --------------------- | --------------- |
| **語法檢查**   | ShellCheck, bash -n   | 腳本語法錯誤    |
| **配置驗證**   | docker-compose config | YAML 和服務配置 |
| **安全掃描**   | Trivy                 | 漏洞和敏感信息  |
| **單元測試**   | 自定義框架            | 函數邏輯        |
| **集成測試**   | docker-compose        | 服務間交互      |
| **端到端測試** | 全流程測試            | 完整應用功能    |

### 🎯 **7. 快速測試指南**

#### **立即測試您的代碼**

```bash
# 1. 運行完整測試套件
cd tests && bash run_all_tests.sh

# 2. 檢查特定文件
docker-compose -f digirunner-open-source/docker-compose.yml config

# 3. 語法檢查腳本
bash -n proxmox9.0/debian13-tool.sh

# 4. 使用 ShellCheck
shellcheck proxmox9.0/debian13-tool.sh
```

#### **CI/CD 測試**

一旦推送到 GitHub，會自動運行：

- 🔍 **Docker 語法檢查**
- 🐚 **Shell 腳本測試**
- 🔗 **Compose 文件驗證**
- 🛡️ **安全掃描**

### 💡 **推薦測試工作流程**

1. **本地開發時**: `bash run_all_tests.sh unit`
2. **功能完成時**: `bash run_all_tests.sh integration`
3. **發佈前**: `bash run_all_tests.sh all`
4. **合併前**: 確保 CI/CD 全部通過

### 🏆 **測試工具總結**

您的專案現在具備：

- ✅ **自動化測試框架** (自定義 shell 腳本)
- ✅ **CI/CD 集成測試** (GitHub Actions)
- ✅ **靜態代碼分析** (ShellCheck, Hadolint)
- ✅ **安全漏洞掃描** (Trivy)
- ✅ **配置驗證** (docker-compose config)
- ✅ **語法檢查** (多種工具)
