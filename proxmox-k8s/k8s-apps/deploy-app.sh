#!/bin/bash

# Kubernetes 應用部署腳本
# 支持 Proxmox 8.0-9.0 環境

# 設置顏色變量
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日誌函數
echo_red() { echo -e "${RED}$1${NC}"; }
echo_green() { echo -e "${GREEN}$1${NC}"; }
echo_yellow() { echo -e "${YELLOW}$1${NC}"; }
echo_blue() { echo -e "${BLUE}$1${NC}"; }

# 檢查 kubectl 是否可用
check_kubectl() {
  if ! command -v kubectl &> /dev/null; then
    echo_red "錯誤：未找到 kubectl 命令"
    echo_yellow "請確保 Kubernetes 集群已正確配置"
    exit 1
  fi
}

# 部署 Nginx 應用
deploy_nginx() {
  echo_yellow "正在部署 Nginx 應用..."

  # 創建 Nginx Deployment
  kubectl create deployment nginx --image=nginx:alpine

  # 暴露服務
  kubectl expose deployment nginx --port=80 --type=NodePort

  # 獲取服務信息
  echo_blue "Nginx 應用部署信息："
  kubectl get deployment nginx
  kubectl get service nginx

  echo_green "Nginx 應用部署完成"
}

# 部署 MySQL 數據庫
deploy_mysql() {
  echo_yellow "正在部署 MySQL 數據庫..."

  # 創建 MySQL 密碼 Secret
  kubectl create secret generic mysql-pass --from-literal=password=rootpass123

  # 創建 MySQL Deployment 和 Service
  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: mysql
spec:
  ports:
  - port: 3306
  selector:
    app: mysql
  clusterIP: None
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mysql
spec:
  selector:
    matchLabels:
      app: mysql
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: mysql
    spec:
      containers:
      - image: mysql:8.0
        name: mysql
        env:
        - name: MYSQL_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mysql-pass
              key: password
        ports:
        - containerPort: 3306
          name: mysql
        volumeMounts:
        - name: mysql-persistent-storage
          mountPath: /var/lib/mysql
      volumes:
      - name: mysql-persistent-storage
        emptyDir: {}
EOF

  echo_blue "MySQL 數據庫部署信息："
  kubectl get deployment mysql
  kubectl get service mysql
  kubectl get secret mysql-pass

  echo_green "MySQL 數據庫部署完成"
}

# 部署 WordPress
deploy_wordpress() {
  echo_yellow "正在部署 WordPress..."

  # 創建 WordPress Deployment 和 Service
  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: wordpress
  labels:
    app: wordpress
spec:
  ports:
    - port: 80
  selector:
    app: wordpress
    tier: frontend
  type: NodePort
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wordpress
  labels:
    app: wordpress
spec:
  selector:
    matchLabels:
      app: wordpress
      tier: frontend
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: wordpress
        tier: frontend
    spec:
      containers:
      - image: wordpress:6.0-apache
        name: wordpress
        env:
        - name: WORDPRESS_DB_HOST
          value: mysql:3306
        - name: WORDPRESS_DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mysql-pass
              key: password
        ports:
        - containerPort: 80
          name: wordpress
EOF

  echo_blue "WordPress 部署信息："
  kubectl get deployment wordpress
  kubectl get service wordpress

  echo_green "WordPress 部署完成"
}

# 部署監控組件
deploy_monitoring() {
  echo_yellow "正在部署監控組件..."

  # 這裡可以部署 Prometheus、Grafana 等監控組件
  echo_blue "監控組件部署選項："
  echo "1. Prometheus"
  echo "2. Grafana"
  echo "3. 完整監控套件"

  echo_yellow "請手動部署監控組件或使用專門的監控腳本"
}

# 顯示應用狀態
show_app_status() {
  echo_blue "當前部署的應用："
  kubectl get deployments
  echo ""
  kubectl get services
  echo ""
  kubectl get pods
}

# 主菜單
show_menu() {
  echo_green "==========================================="
  echo_green "Kubernetes 應用部署菜單"
  echo_green "==========================================="
  echo "1. 部署 Nginx 應用"
  echo "2. 部署 MySQL 數據庫"
  echo "3. 部署 WordPress"
  echo "4. 部署監控組件"
  echo "5. 顯示應用狀態"
  echo "6. 退出"
  echo_green "==========================================="
}

# 主函數
main() {
  check_kubectl

  while true; do
    show_menu
    read -p "請選擇操作 [1-6]: " choice

    case $choice in
      1)
        deploy_nginx
        echo ""
        read -p "按回車鍵繼續..."
        ;;
      2)
        deploy_mysql
        echo ""
        read -p "按回車鍵繼續..."
        ;;
      3)
        deploy_wordpress
        echo ""
        read -p "按回車鍵繼續..."
        ;;
      4)
        deploy_monitoring
        echo ""
        read -p "按回車鍵繼續..."
        ;;
      5)
        show_app_status
        echo ""
        read -p "按回車鍵繼續..."
        ;;
      6)
        echo_green "退出應用部署腳本"
        exit 0
        ;;
      *)
        echo_red "無效選擇，請重新輸入"
        read -p "按回車鍵繼續..."
        ;;
    esac
  done
}

# 執行主函數
main
