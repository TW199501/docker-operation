# syntax=docker/dockerfile:1
FROM haproxy:trixie

# 預設帶入專案中的 haproxy 設定檔（如有 volume 掛載會被覆蓋）
COPY haproxy/haproxy.cfg /usr/local/etc/haproxy/haproxy.cfg
