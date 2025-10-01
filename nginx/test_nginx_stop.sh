#!/bin/bash

# 测试nginx停止功能的简化脚本
echo "檢查是否有正在運行的 nginx 進程..."
if pgrep nginx > /dev/null; then
  echo "停止 nginx 進程..."
  # 使用更温和的方式停止nginx
  sudo systemctl stop nginx 2>/dev/null || true
  # 如果systemctl不可用，尝试发送TERM信号
  sudo pkill -TERM nginx 2>/dev/null || true
  # 等待一段时间让进程正常退出
  sleep 5
  # 检查是否还有nginx进程在运行
  if pgrep nginx > /dev/null; then
    echo "仍有 nginx 進程在運行，強制終止..."
    sudo pkill -KILL nginx 2>/dev/null || true
    sleep 2
  fi
  echo "nginx 進程已停止"
else
  echo "沒有發現運行中的 nginx 進程"
fi

# 清理PID文件
sudo rm -f /run/nginx.pid || true

echo "清理完成"
