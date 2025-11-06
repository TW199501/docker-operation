# Proxmox Kubernetes 項目 Makefile

# 變量定義
PROJECT_DIR := $(PWD)
SCRIPTS_DIR := $(PROJECT_DIR)/k8s-cluster
APPS_DIR := $(PROJECT_DIR)/k8s-apps
DOCS_DIR := $(PROJECT_DIR)/docs

# 顏色定義
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[1;33m
NC := \033[0m # No Color

.PHONY: help init master worker reset app docs clean

help:
	@echo "$(GREEN)Proxmox Kubernetes 項目管理$(NC)"
	@echo "使用方法: make [目標]"
	@echo ""
	@echo "可用目標:"
	@echo "  init     - 初始化項目目錄和權限"
	@echo "  master   - 準備 Master 節點腳本"
	@echo "  worker   - 準備 Worker 節點腳本"
	@echo "  reset    - 準備集群重置腳本"
	@echo "  app      - 準備應用部署腳本"
	@echo "  docs     - 顯示文檔列表"
	@echo "  clean    - 清理臨時文件"
	@echo "  help     - 顯示此幫助信息"

init:
	@echo "$(YELLOW)初始化項目...$(NC)"
	chmod +x $(SCRIPTS_DIR)/create-cluster.sh
	chmod +x $(SCRIPTS_DIR)/join-worker.sh
	chmod +x $(SCRIPTS_DIR)/reset-cluster.sh
	chmod +x $(APPS_DIR)/deploy-app.sh
	@echo "$(GREEN)項目初始化完成$(NC)"

master:
	@echo "$(YELLOW)Master 節點腳本準備完成$(NC)"
	@echo "請在 Master 節點執行:"
	@echo "  cd $(PROJECT_DIR)"
	@echo "  ./k8s-cluster/create-cluster.sh"

worker:
	@echo "$(YELLOW)Worker 節點腳本準備完成$(NC)"
	@echo "請在 Worker 節點執行:"
	@echo "  cd $(PROJECT_DIR)"
	@echo "  ./k8s-cluster/join-worker.sh \"[從 Master 獲取的 join 命令]\""

reset:
	@echo "$(YELLOW)集群重置腳本準備完成$(NC)"
	@echo "警告: 此操作將完全重置 Kubernetes 節點"
	@echo "請執行: ./k8s-cluster/reset-cluster.sh"

app:
	@echo "$(YELLOW)應用部署腳本準備完成$(NC)"
	@echo "請執行: ./k8s-apps/deploy-app.sh"

docs:
	@echo "$(GREEN)項目文檔列表:$(NC)"
	@echo "  1. 架構設計: $(DOCS_DIR)/architecture.md"
	@echo "  2. 部署指南: $(DOCS_DIR)/deployment-guide.md"
	@echo "  3. 故障排除: $(DOCS_DIR)/troubleshooting.md"

clean:
	@echo "$(YELLOW)清理臨時文件...$(NC)"
	find . -name "*.tmp" -delete
	find . -name "*.log" -delete
	@echo "$(GREEN)清理完成$(NC)"

install: init
	@echo "$(GREEN)項目安裝完成$(NC)"
	@echo "請參閱文檔開始部署: make docs"
