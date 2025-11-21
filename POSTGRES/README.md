PG+Reids

```

services:
  postgres:
    image: pgvector/pgvector:pg18
    container_name: postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_INITDB_ARGS: "--encoding=UTF8 --locale=C"
      TZ: Asia/Taipei
    ports:
      - "0.0.0.0:5532:5432"
    volumes:
      - ./pgdata:/var/lib/postgresql
      - ./init:/docker-entrypoint-initdb.d
    # --- 添加健康檢查設定 ---
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $$POSTGRES_USER -d $$POSTGRES_DB || exit 1"]
      interval: 10s # 每 10 秒執行一次檢查
      timeout: 5s   # 檢查超時時間
      retries: 5    # 重試 5 次失敗後標記為不健康
      start_period: 30s # 容器啟動後的初始化等待時間
  redis:
    image: redis:alpine
    container_name: redis
    restart: always
    environment:
      - REDIS_PASSWORD=${REDIS_PASSWORD}
    ports:
      - "0.0.0.0:6479:6379"
    command: ["redis-server", "--requirepass", "${REDIS_PASSWORD}"]
    volumes:
      - ./redis_data:/data
  

networks:
  default:
    external: true
    name: elfnet

```
