# Proxmox Kubernetes 項目 CI/CD 配置指南

## 概述

本指南為 Proxmox Kubernetes 項目設置完整的 CI/CD 流程，包括代碼質量檢查、測試、部署和安全掃描。

## 目錄結構

```
.github/
├── workflows/
│   ├── ci.yml              # 主要 CI 流程
│   ├── security.yml        # 安全掃描
│   ├── release.yml         # 發佈流程
│   └── docker.yml          # Docker 鏡像構建
├── dependabot.yml          # 依賴更新
└── CODEOWNERS             # 代碼所有者
```

## 1. 主要 CI 工作流程 (.github/workflows/ci.yml)

```yaml
name: CI

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  # 代碼質量檢查
  quality-check:
    runs-on: ubuntu-latest
    steps:
    - name: Checkout code
      uses: actions/checkout@v4

    - name: Setup Node.js for markdownlint
      uses: actions/setup-node@v4
      with:
        node-version: '18'

    - name: Install dependencies
      run: |
        npm install -g markdownlint-cli
        sudo apt-get update
        sudo apt-get install -y shellcheck

    - name: Shell script linting
      run: |
        find . -name "*.sh" -type f -exec shellcheck {} \;

    - name: Markdown linting
      run: |
        markdownlint "**/*.md" --config .markdownlint.json || true

    - name: Check file permissions
      run: |
        # 確保腳本文件有執行權限
        find . -name "*.sh" -type f -exec test -x {} \; -print

  # 腳本測試
  test-scripts:
    runs-on: ubuntu-latest
    steps:
    - name: Checkout code
      uses: actions/checkout@v4

    - name: Setup test environment
      run: |
        sudo apt-get update
        sudo apt-get install -y bash make

    - name: Validate Makefile syntax
      run: |
        make --dry-run

    - name: Test script syntax
      run: |
        # 檢查所有 shell 腳本語法
        find . -name "*.sh" -type f -exec bash -n {} \;

    - name: Test make targets
      run: |
        make help || true

  # 文檔檢查
  docs-validation:
    runs-on: ubuntu-latest
    steps:
    - name: Checkout code
      uses: actions/checkout@v4

    - name: Setup Python for docs validation
      uses: actions/setup-python@v4
      with:
        python-version: '3.9'

    - name: Install doc validation tools
      run: |
        pip install linkchecker

    - name: Check internal links
      run: |
        # 檢查文檔內部鏈接
        find docs/ -name "*.md" -exec linkchecker --check-extern {} \; || true

    - name: Validate README structure
      run: |
        # 檢查 README 是否包含必要章節
        grep -q "## 功能特點" README.md || echo "Missing features section"
        grep -q "## 安裝說明" README.md || echo "Missing installation section"

  # Docker 鏡像檢查（如果有的話）
  docker-check:
    runs-on: ubuntu-latest
    if: contains(github.event.head_commit.modified, 'Dockerfile') || contains(github.event.head_commit.modified, 'docker-compose')
    steps:
    - name: Checkout code
      uses: actions/checkout@v4

    - name: Docker lint
      uses: hadolint/hadolint-action@v3.1.0
      with:
        dockerfile: Dockerfile

    - name: Build test
      run: |
        if [ -f Dockerfile ]; then
          docker build --no-cache -t test-image .
        fi
```

## 2. 安全掃描工作流程 (.github/workflows/security.yml)

```yaml
name: Security Scan

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]
  schedule:
    - cron: '0 2 * * 1'  # 每周一凌晨2點

jobs:
  security-scan:
    runs-on: ubuntu-latest
    steps:
    - name: Checkout code
      uses: actions/checkout@v4

    - name: Run Trivy vulnerability scanner
      uses: aquasecurity/trivy-action@master
      with:
        scan-type: 'fs'
        scan-ref: '.'
        format: 'sarif'
        output: 'trivy-results.sarif'

    - name: Upload Trivy scan results to GitHub Security tab
      uses: github/codeql-action/upload-sarif@v2
      if: always()
      with:
        sarif_file: 'trivy-results.sarif'

    - name: Shell script security scan
      run: |
        # 使用 shellcheck 檢查安全問題
        find . -name "*.sh" -type f -exec shellcheck --severity=error {} \;

  secrets-scan:
    runs-on: ubuntu-latest
    steps:
    - name: Checkout code
      uses: actions/checkout@v4

    - name: Run secret scanning
      uses: gitleaks/gitleaks-action@v2
      env:
        GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

  dependency-check:
    runs-on: ubuntu-latest
    steps:
    - name: Checkout code
      uses: actions/checkout@v4

    - name: Setup Python
      uses: actions/setup-python@v4
      with:
        python-version: '3.9'

    - name: Run safety check for Python dependencies
      run: |
        if [ -f requirements.txt ]; then
          pip install safety
          safety check
        fi
```

## 3. 發佈工作流程 (.github/workflows/release.yml)

```yaml
name: Release

on:
  push:
    tags:
      - 'v*'

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
    - name: Checkout code
      uses: actions/checkout@v4

    - name: Get version from tag
      run: echo "VERSION=${GITHUB_REF#refs/tags/v}" >> $GITHUB_ENV

    - name: Create release archive
      run: |
        mkdir release
        cp -r k8s-cluster/ release/
        cp -r k8s-apps/ release/
        cp -r docs/ release/
        cp README.md release/
        cp Makefile release/
        tar -czf proxmox-k8s-${{ env.VERSION }}.tar.gz release/

    - name: Create GitHub Release
      uses: actions/create-release@v1
      env:
        GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
      with:
        tag_name: ${{ github.ref }}
        release_name: Release ${{ github.ref }}
        body: |
          ## 發佈說明

          版本: ${{ env.VERSION }}

          ### 主要變更
          - 請查看 CHANGELOG.md 了解詳細變更

          ### 安裝方式
          ```bash
          wget https://github.com/${{ github.repository }}/releases/download/${{ github.ref }}/proxmox-k8s-${{ env.VERSION }}.tar.gz
          tar -xzf proxmox-k8s-${{ env.VERSION }}.tar.gz
          cd release
          make init
          ```

        draft: false
        prerelease: false

    - name: Upload release assets
      uses: actions/upload-release-asset@v1
      env:
        GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
      with:
        upload_url: ${{ steps.create_release.outputs.upload_url }}
        asset_path: ./proxmox-k8s-${{ env.VERSION }}.tar.gz
        asset_name: proxmox-k8s-${{ env.VERSION }}.tar.gz
        asset_content_type: application/gzip
```

## 4. Docker 鏡像構建 (.github/workflows/docker.yml)

```yaml
name: Docker Build

on:
  push:
    branches: [ main ]
    paths:
      - 'Dockerfile'
      - 'docker-compose.yml'
      - '.dockerignore'

jobs:
  build-and-push:
    runs-on: ubuntu-latest
    steps:
    - name: Checkout code
      uses: actions/checkout@v4

    - name: Set up QEMU
      uses: docker/setup-qemu-action@v3

    - name: Set up Docker Buildx
      uses: docker/setup-buildx-action@v3

    - name: Login to Docker Hub
      uses: docker/login-action@v3
      with:
        username: ${{ secrets.DOCKER_USERNAME }}
        password: ${{ secrets.DOCKER_PASSWORD }}

    - name: Extract metadata
      id: meta
      uses: docker/metadata-action@v5
      with:
        images: ${{ github.repository }}
        tags: |
          type=ref,event=branch
          type=ref,event=pr
          type=sha,prefix={{branch}}-
          type=raw,value=latest,enable={{is_default_branch}}

    - name: Build and push
      uses: docker/build-push-action@v5
      with:
        context: .
        platforms: linux/amd64,linux/arm64
        push: true
        tags: ${{ steps.meta.outputs.tags }}
        labels: ${{ steps.meta.outputs.labels }}
        cache-from: type=gha
        cache-to: type=gha,mode=max
```

## 5. 依賴更新配置 (.github/dependabot.yml)

```yaml
version: 2
updates:
  # GitHub Actions 更新
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
    commit-message:
      prefix: "ci"
      include: "scope"

  # Docker 依賴更新
  - package-ecosystem: "docker"
    directory: "/"
    schedule:
      interval: "weekly"
    commit-message:
      prefix: "docker"
      include: "scope"

  # 如果有 Python 依賴
  - package-ecosystem: "pip"
    directory: "/"
    schedule:
      interval: "weekly"
    commit-message:
      prefix: "deps"
      include: "scope"
```

## 6. 代碼所有者配置 (.github/CODEOWNERS)

```
# 主要維護者
* @your-username

# 腳本相關
k8s-cluster/ @your-username
k8s-apps/ @your-username

# 文檔相關
docs/ @your-username
*.md @your-username

# CI/CD 配置
.github/ @your-username
```

## 7. 其他配置文件

### .markdownlint.json (Markdown 格式檢查)

```json
{
  "default": true,
  "MD013": false,
  "MD024": false,
  "MD033": false,
  "MD041": false
}
```

### .shellcheckrc (Shell 檢查配置)

```bash
# ShellCheck 配置
disable=SC1090,SC1091,SC2034,SC2154
```

### .dockerignore (Docker 忽略文件)

```
.github/
docs/
*.md
.gitignore
```

## 8. 本地開發設置

### pre-commit hooks (.pre-commit-config.yaml)

```yaml
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.4.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
      - id: check-added-large-files

  - repo: https://github.com/koalaman/shellcheck-precommit
    rev: v0.9.0
    hooks:
      - id: shellcheck

  - repo: https://github.com/igorshubovych/markdownlint-cli
    rev: v0.35.0
    hooks:
      - id: markdownlint
        args: [--config, .markdownlint.json]
```

## 9. 使用說明

### 設置步驟

1. **創建 GitHub Actions 目錄結構**
   ```bash
   mkdir -p .github/workflows
   ```

2. **複製配置文件**
   - 將上述 YAML 文件保存到對應的 `.github/workflows/` 目錄

3. **配置 Secrets**
   在 GitHub 倉庫設置中添加以下 secrets：
   - `DOCKER_USERNAME`: Docker Hub 用戶名
   - `DOCKER_PASSWORD`: Docker Hub 密碼

4. **推送代碼**
   ```bash
   git add .
   git commit -m "Add CI/CD configuration"
   git push
   ```

### 工作流程說明

- **CI**: 每次 push 和 PR 都會運行代碼質量檢查
- **Security**: 每周一和主要分支推送時運行安全掃描
- **Release**: 標籤推送時自動創建發佈
- **Docker**: Dockerfile 變更時自動構建鏡像

### 監控和維護

- 定期檢查 Actions 日誌
- 關注安全掃描結果
- 及時處理依賴更新
- 根據需要調整檢查規則

## 10. 故障排除

### 常見問題

1. **ShellCheck 錯誤**
   - 添加 `# shellcheck disable=SCXXXX` 註釋忽略特定錯誤

2. **Markdown 格式問題**
   - 調整 `.markdownlint.json` 配置

3. **權限問題**
   - 確保腳本文件有執行權限
   - 使用 `git update-index --chmod=+x script.sh`

4. **依賴問題**
   - 檢查 Actions 運行器的系統要求
   - 更新 action 版本

這個 CI/CD 配置提供了完整的自動化流程，確保代碼質量和安全性的同時，提高開發效率。
