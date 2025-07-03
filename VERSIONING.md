# 版本管理指南

本項目使用語義化版本控制 (Semantic Versioning)。

## 如何更新版本

### 使用 bump-version 腳本 (推薦)

#### Windows 用戶
```bash
# 更新修訂號 (1.0.0 -> 1.0.1)
.\bump-version.bat

# 更新次版本號 (1.0.1 -> 1.1.0)
.\bump-version.bat minor

# 更新主版本號 (1.1.0 -> 2.0.0)
.\bump-version.bat major
```

#### Linux/Mac 用戶
```bash
# 添加執行權限
chmod +x bump-version.sh

# 更新修訂號 (1.0.0 -> 1.0.1)
./bump-version.sh

# 更新次版本號 (1.0.1 -> 1.1.0)
./bump-version.sh minor

# 更新主版本號 (1.1.0 -> 2.0.0)
./bump-version.sh major
```

## 版本號規則

- **主版本號 (MAJOR)**: 當你做了不兼容的 API 修改
- **次版本號 (MINOR)**: 當你做了向下兼容的功能性新增
- **修訂號 (PATCH)**: 當你做了向下兼容的問題修正

## 自動化流程

1. 腳本會自動更新 `VERSION` 文件
2. 更新所有子目錄中的 `Dockerfile` 中的 `LABEL version`
3. 創建 Git 提交
4. 創建 Git 標籤

## 注意事項

- 更新版本後，請記得推送到遠程倉庫：
  ```
  git push origin main --tags
  ```
- 確保在更新版本前，所有更改都已暫存 (git add)
