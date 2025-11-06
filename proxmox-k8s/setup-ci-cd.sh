#!/bin/bash

# Proxmox Kubernetes 項目 CI/CD 設置腳本
# 用法：./setup-ci-cd.sh

set -e

echo "🚀 設置 Proxmox Kubernetes 項目的 CI/CD..."

# 創建目錄結構
echo "📁 創建 GitHub Actions 目錄結構..."
mkdir -p .github/workflows

# 複製工作流程文件
echo "📋 複製 CI 工作流程..."
cp .github-workflows-ci.yml .github/workflows/ci.yml

# 創建其他配置文件
echo "⚙️  創建配置文件..."

# .markdownlint.json
cat > .markdownlint.json << 'EOF'
{
  "default": true,
  "MD013": false,
  "MD024": false,
  "MD033": false,
  "MD041": false
}
EOF

# .shellcheckrc
cat > .shellcheckrc << 'EOF'
# ShellCheck 配置
disable=SC1090,SC1091,SC2034,SC2154
EOF

# .dockerignore
cat > .dockerignore << 'EOF'
.github/
docs/
*.md
.gitignore
EOF

# .pre-commit-config.yaml
cat > .pre-commit-config.yaml << 'EOF'
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
EOF

echo "✅ CI/CD 設置完成！"
echo ""
echo "📝 下一步操作："
echo "1. 檢查創建的文件："
echo "   ls -la .github/workflows/"
echo "   ls -la .*.json .*.yaml .*.rc"
echo ""
echo "2. 提交到 Git 並推送："
echo "   git add ."
echo "   git commit -m 'Add CI/CD configuration'"
echo "   git push"
echo ""
echo "3. 在 GitHub 設置中配置以下 Secrets（如果需要）："
echo "   - DOCKER_USERNAME"
echo "   - DOCKER_PASSWORD"
echo ""
echo "4. 檢查 Actions 運行狀態："
echo "   訪問：https://github.com/YOUR_USERNAME/YOUR_REPO/actions"
