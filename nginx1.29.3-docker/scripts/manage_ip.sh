#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "用法: $0 <allow|deny> <IP地址> <配置文件路徑>" >&2
  echo "示例: $0 allow 192.168.1.100 /etc/nginx/conf.d/ip_whitelist.conf" >&2
}

if [ "$#" -ne 3 ]; then
  usage
  exit 1
fi

ACTION="$1"
IP_ADDRESS="$2"
CONFIG_FILE="$3"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "配置文件不存在: $CONFIG_FILE" >&2
  exit 1
fi

case "$ACTION" in
  allow)
    if grep -q "allow $IP_ADDRESS;" "$CONFIG_FILE"; then
      echo "IP $IP_ADDRESS 已在白名單中"
    else
      # 在 deny all; 之前插入 allow 規則
      sed -i "/deny all;/i\    allow $IP_ADDRESS;" "$CONFIG_FILE"
      echo "已添加 IP $IP_ADDRESS 到白名單"
    fi
    ;;
  deny)
    if grep -q "allow $IP_ADDRESS;" "$CONFIG_FILE"; then
      sed -i "/allow $IP_ADDRESS;/d" "$CONFIG_FILE"
      echo "已從白名單中移除 IP $IP_ADDRESS"
    else
      echo "IP $IP_ADDRESS 不在白名單中"
    fi
    ;;
  *)
    echo "無效的動作，請使用 'allow' 或 'deny'" >&2
    exit 1
    ;;
esac
