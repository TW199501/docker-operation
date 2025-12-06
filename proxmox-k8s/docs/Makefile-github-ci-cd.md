# Makefile 與 GitHub CI/CD 在資料庫專案中的整合

## 簡介

Makefile 與 GitHub Actions 的結合為資料庫專案提供了強大的自動化能力。通過這種整合，我們可以實現從資料庫部署、測試到遷移的完整自動化流程，大大提高開發效率和系統可靠性。

## GitHub Actions 工作流程

### 基礎 CI/CD 配置

```yaml
name: Database CI/CD

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  database-test:
    runs-on: ubuntu-latest
    
    services:
      sqlserver:
        image: mcr.microsoft.com/mssql/server:2019-latest
        env:
          SA_PASSWORD: YourStrong@Passw0rd
          ACCEPT_EULA: Y
        ports:
          - 1433:1433
        options: >-
          --health-cmd="/opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P 'YourStrong@Passw0rd' -Q 'SELECT 1'"
          --health-interval=10s
          --health-timeout=5s
          --health-retries=5

    steps:
    - uses: actions/checkout@v3
    
    - name: Install dependencies
      run: |
        sudo apt-get update
        sudo apt-get install -y make
        
    - name: Setup database
      run: make dev-setup
      
    - name: Run tests
      run: make test
      
    - name: Generate documentation
      run: make docs
```

## Makefile 與 CI/CD 的整合

### 擴展的 Makefile 支持 CI/CD

```makefile
# CI/CD 專用目標
.PHONY: ci-setup ci-test ci-deploy ci-cleanup

# CI 環境設置
ci-setup:
	@echo "Setting up CI environment..."
	sqlcmd -S localhost -U sa -P $(SA_PASSWORD) -Q "CREATE DATABASE ci_test"
	sqlcmd -S localhost -U sa -P $(SA_PASSWORD) -d ci_test -i schema/full-schema.sql

# CI 測試執行
ci-test:
	@echo "Running CI tests..."
	sqlcmd -S localhost -U sa -P $(SA_PASSWORD) -d ci_test -i tests/ci-setup.sql
	sqlcmd -S localhost -U sa -P $(SA_PASSWORD) -d ci_test -i tests/unit-tests.sql
	sqlcmd -S localhost -U sa -P $(SA_PASSWORD) -d ci_test -i tests/integration-tests.sql

# CI 部署
ci-deploy:
	@echo "Deploying to CI environment..."
	sqlcmd -S $(DEPLOY_SERVER) -U $(DEPLOY_USER) -P $(DEPLOY_PASSWORD) -d $(DEPLOY_DATABASE) -i schema/deployment.sql

# CI 清理
ci-cleanup:
	@echo "Cleaning up CI environment..."
	sqlcmd -S localhost -U sa -P $(SA_PASSWORD) -Q "DROP DATABASE ci_test"
```

## 多環境支持

### 環境變量配置

```makefile
# 環境變量支持
ENV ?= development
DB_SERVER := $(shell cat config/$(ENV)/server.txt)
DB_NAME := $(shell cat config/$(ENV)/database.txt)
DB_USER := $(shell cat config/$(ENV)/user.txt)
DB_PASSWORD := $(shell cat config/$(ENV)/password.txt)

# 環境特定部署
deploy:
	sqlcmd -S $(DB_SERVER) -U $(DB_USER) -P $(DB_PASSWORD) -d $(DB_NAME) -i schema/main.sql

# 多環境目標
deploy-dev:
	$(MAKE) ENV=development deploy

deploy-staging:
	$(MAKE) ENV=staging deploy

deploy-prod:
	$(MAKE) ENV=production deploy
```

## 數據庫遷移與版本控制

### GitHub Actions 自動化遷移

```yaml
name: Database Migration

on:
  push:
    branches: [ main ]
    paths:
      - 'migrations/**'

jobs:
  migrate:
    runs-on: ubuntu-latest
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Install dependencies
      run: |
        sudo apt-get update
        sudo apt-get install -y make
        
    - name: Run migrations
      run: make migrate
      env:
        DB_SERVER: ${{ secrets.DB_SERVER }}
        DB_NAME: ${{ secrets.DB_NAME }}
        DB_USER: ${{ secrets.DB_USER }}
        DB_PASSWORD: ${{ secrets.DB_PASSWORD }}
```

### 對應的 Makefile 遷移目標

```makefile
# 數據庫遷移
MIGRATIONS_DIR = migrations
VERSION_FILE = .db_version

# 獲取當前版本
CURRENT_VERSION := $(shell cat $(VERSION_FILE) 2>/dev/null || echo "0")

# 執行遷移
migrate:
	@echo "Current database version: $(CURRENT_VERSION)"
	@for migration in $(MIGRATIONS_DIR)/*.sql; do \
		version=$$(basename $$migration | cut -d'_' -f1); \
		if [ "$$version" -gt "$(CURRENT_VERSION)" ]; then \
			echo "Applying migration $$migration"; \
			sqlcmd -S $(DB_SERVER) -U $(DB_USER) -P $(DB_PASSWORD) -d $(DB_NAME) -i $$migration; \
			echo $$version > $(VERSION_FILE); \
		fi; \
	done

# 回滾遷移
rollback:
	@echo "Rolling back last migration..."
	@last_version=$$(cat $(VERSION_FILE)); \
	prev_version=$$(ls $(MIGRATIONS_DIR) | grep "^$$((last_version-1))_" | cut -d'_' -f1); \
	if [ -n "$$prev_version" ]; then \
		rollback_file=$(MIGRATIONS_DIR)/$${last_version}_rollback.sql; \
		if [ -f "$$rollback_file" ]; then \
			sqlcmd -S $(DB_SERVER) -U $(DB_USER) -P $(DB_PASSWORD) -d $(DB_NAME) -i $$rollback_file; \
			echo $$prev_version > $(VERSION_FILE); \
		else \
			echo "Rollback file not found: $$rollback_file"; \
		fi; \
	else \
		echo "No previous version found"; \
	fi
```

## 測試報告與質量門戶

### GitHub Actions 測試報告

```yaml
name: Database Testing

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    
    services:
      sqlserver:
        image: mcr.microsoft.com/mssql/server:2019-latest
        env:
          SA_PASSWORD: YourStrong@Passw0rd
          ACCEPT_EULA: Y
        ports:
          - 1433:1433

    steps:
    - uses: actions/checkout@v3
    
    - name: Setup and Test
      run: |
        make ci-setup
        make ci-test > test-results.txt
        make ci-cleanup
        
    - name: Publish Test Results
      uses: actions/upload-artifact@v3
      if: always()
      with:
        name: test-results
        path: test-results.txt
```

## 安全與密碼管理

### 安全的環境變量使用

```makefile
# 安全的密碼處理
DB_CONNECTION_STRING := "Server=$(DB_SERVER);Database=$(DB_NAME);User Id=$(DB_USER);Password=$(DB_PASSWORD);"

# 使用連接字符串執行
execute-sql:
	sqlcmd -S $(DB_SERVER) -U $(DB_USER) -P $(DB_PASSWORD) -d $(DB_NAME) -i $(SQL_FILE)

# 敏感數據清理
clean-secrets:
	@echo "Cleaning up sensitive data..."
	rm -f .db_version
	rm -f test-results.txt
```

## 實際應用場景

### 1. 拉取請求自動測試
```yaml
# 在 PR 創建時自動運行測試
on:
  pull_request:
    types: [opened, synchronize]
```

### 2. 自動部署到測試環境
```yaml
# 在合併到 main 分支時自動部署
on:
  push:
    branches: [main]
```

### 3. 定期備份任務
```yaml
# 每天自動備份
on:
  schedule:
    - cron: '0 2 * * *'  # 每天凌晨 2 點
```

## 總結

通過 Makefile 與 GitHub Actions 的結合，您可以實現：

1. **完全自動化的資料庫 CI/CD 流程**
2. **多環境部署支持**
3. **自動化測試和質量檢查**
4. **數據庫遷移和版本管理**
5. **安全的密碼和敏感信息管理**
6. **測試報告和結果可視化**
7. **定期維護任務自動化**

這確實是一個非常強大的組合，可以大大提高資料庫開發和運維的效率與可靠性！
