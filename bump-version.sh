#!/bin/bash

# 獲取當前版本
CURRENT_VERSION=$(cat VERSION)
echo "當前版本: $CURRENT_VERSION"

# 解析版本號
IFS='.' read -r -a VERSION_PARTS <<< "$CURRENT_VERSION"
MAJOR=${VERSION_PARTS[0]}
MINOR=${VERSION_PARTS[1]}
PATCH=${VERSION_PARTS[2]}

# 檢查參數
case "$1" in
  major)
    NEW_MAJOR=$((MAJOR + 1))
    NEW_VERSION="$NEW_MAJOR.0.0"
    ;;
  minor)
    NEW_MINOR=$((MINOR + 1))
    NEW_VERSION="$MAJOR.$NEW_MINOR.0"
    ;;
  patch|*)
    NEW_PATCH=$((PATCH + 1))
    NEW_VERSION="$MAJOR.$MINOR.$NEW_PATCH"
    ;;
esac

# 更新版本文件
echo "新版本: $NEW_VERSION"
echo $NEW_VERSION > VERSION

# 更新 Dockerfile 中的 LABEL version（如果存在）
sed -i "s/LABEL version=.*/LABEL version=$NEW_VERSION/" */Dockerfile 2>/dev/null || true

# 提交更改
git add VERSION */Dockerfile
git commit -m "Bump version to $NEW_VERSION"
git tag -a "v$NEW_VERSION" -m "Version $NEW_VERSION"

echo "版本已更新為 $NEW_VERSION 並創建標籤 v$NEW_VERSION"
echo "請使用 'git push origin main --tags' 推送到遠程倉庫"
