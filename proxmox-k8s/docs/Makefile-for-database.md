# Makefile 在 T-SQL 資料庫專案中的應用

## 簡介

Makefile 不僅適用於程式碼編譯項目，在 T-SQL 資料庫專案中同樣發揮著強大的作用。通過 Makefile，我們可以自動化資料庫部署、測試、備份等各種操作，大大提高開發效率和減少人為錯誤。

## 核心優勢

### 1. **自動化資料庫部署**

```makefile
# 自動部署資料庫結構
deploy-schema:
 sqlcmd -S server -d database -i schema/tables.sql
 sqlcmd -S server -d database -i schema/views.sql
 sqlcmd -S server -d database -i schema/stored-procedures.sql

# 部署測試數據
deploy-test-data:
 sqlcmd -S server -d database -i data/test-data.sql
```

**好處**：

- 一鍵部署整個資料庫環境
- 確保部署順序正確
- 減少手動執行錯誤

### 2. **資料庫版本管理**

```makefile
# 資料庫遷移
migrate:
 sqlcmd -S server -d database -i migrations/$(VERSION).sql

# 回滾遷移
rollback:
 sqlcmd -S server -d database -i migrations/$(VERSION)_rollback.sql
```

**好處**：

- 標準化的遷移流程
- 易於版本控制
- 支持回滾操作

### 3. **測試自動化**

```makefile
# 執行單元測試
test:
 sqlcmd -S server -d test_database -i tests/setup.sql
 sqlcmd -S server -d test_database -i src/procedures.sql
 sqlcmd -S server -d test_database -i tests/unit-tests.sql
 sqlcmd -S server -d test_database -i tests/cleanup.sql

# 性能測試
perf-test:
 sqlcmd -S server -d database -i tests/performance-tests.sql
```

**好處**：

- 自動化測試執行
- 測試環境隔離
- 測試結果一致性

### 4. **資料庫備份與恢復**

```makefile
# 備份資料庫
backup:
 sqlcmd -S server -Q "BACKUP DATABASE [$(DB_NAME)] TO DISK = '$(BACKUP_PATH)'"

# 恢復資料庫
restore:
 sqlcmd -S server -Q "RESTORE DATABASE [$(DB_NAME)] FROM DISK = '$(BACKUP_PATH)'"
```

**好處**：

- 標準化備份流程
- 快速恢復操作
- 易於腳本化

### 5. **環境管理**

```makefile
# 創建開發環境
dev-setup:
 sqlcmd -S localhost -Q "CREATE DATABASE dev_$(PROJECT)"
 sqlcmd -S localhost -d dev_$(PROJECT) -i schema/full-schema.sql

# 創建測試環境
test-setup:
 sqlcmd -S localhost -Q "CREATE DATABASE test_$(PROJECT)"
 sqlcmd -S localhost -d test_$(PROJECT) -i schema/full-schema.sql
```

**好處**：

- 快速環境搭建
- 環境一致性保證
- 簡化新成員加入流程

### 6. **資料庫文檔生成**

```makefile
# 生成資料庫文檔
docs:
 sqlcmd -S server -d database -i scripts/generate-docs.sql > docs/database-schema.md

# 生成 ER 圖
er-diagram:
 sqlcmd -S server -d database -i scripts/generate-er-diagram.sql
```

**好處**：

- 自動化文檔生成
- 保持文檔與代碼同步
- 節省文檔維護時間

### 7. **資料庫清理**

```makefile
# 清理測試數據
clean-test:
 sqlcmd -S server -d test_database -i scripts/cleanup-test-data.sql

# 重置開發環境
reset-dev:
 sqlcmd -S server -Q "DROP DATABASE dev_$(PROJECT)"
 sqlcmd -S server -Q "CREATE DATABASE dev_$(PROJECT)"
 sqlcmd -S server -d dev_$(PROJECT) -i schema/full-schema.sql
```

**好處**：

- 快速清理和重置
- 保持環境清潔
- 簡化調試流程

## 與 T-SQL 的集成優勢

### 腳本組織

```makefile
# 按功能組織 T-SQL 腳本
SCRIPTS_DIR = src
TABLES_DIR = $(SCRIPTS_DIR)/tables
VIEWS_DIR = $(SCRIPTS_DIR)/views
PROCEDURES_DIR = $(SCRIPTS_DIR)/procedures

deploy-all: deploy-tables deploy-views deploy-procedures

deploy-tables:
 for file in $(TABLES_DIR)/*.sql; do \
  sqlcmd -S server -d database -i $$file; \
 done
```

### 參數化執行

```makefile
# 支持環境變量
DB_SERVER ?= localhost
DB_NAME ?= mydatabase
DB_USER ?= sa

deploy:
 sqlcmd -S $(DB_SERVER) -d $(DB_NAME) -U $(DB_USER) -i schema/main.sql
```

## 使用示例

### 基本操作

```bash
# 部署資料庫結構
make deploy-schema

# 執行測試
make test

# 備份資料庫
make backup

# 生成文檔
make docs
```

### 環境管理

```bash
# 設置開發環境
make dev-setup

# 設置測試環境
make test-setup

# 清理測試環境
make clean-test
```

## 總結

在 T-SQL 資料庫專案中，Makefile 提供了以下核心價值：

1. **提高效率**：自動化重複的資料庫操作
2. **減少錯誤**：標準化執行流程
3. **環境一致性**：確保不同環境下的相同行為
4. **團隊協作**：統一的操作接口
5. **版本控制**：與資料庫腳本一起管理
6. **快速部署**：簡化部署和測試流程

即使對於純資料庫專案，Makefile 仍然是非常有用的工具！
