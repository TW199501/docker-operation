

# 最短可行（主機預先建目錄 + docker run）

```bash
# 主機上準備掛載目錄
sudo mkdir -p /vol2/1000/ssd/app-data/mssql2022/{data,log,backup}
sudo chown -R 10001:0 /vol2/1000/ssd/app-data/mssql2022
sudo chmod -R 770 /vol2/1000/ssd/app-data/mssql2022

# 啟動容器（SELinux 主機建議加 :Z）
docker run -d --name mssql2022 \
  -e ACCEPT_EULA=Y \
  -e MSSQL_SA_PASSWORD='YourStrong!Passw0rd' \
  -e MSSQL_DATA_DIR=/var/opt/mssql/data \
  -e MSSQL_LOG_DIR=/var/opt/mssql/log \
  -e MSSQL_BACKUP_DIR=/var/opt/mssql/backup \
  -p 1433:1433 \
  -v /vol2/1000/ssd/app-data/mssql2022:/var/opt/mssql:Z \
  --user 10001:0 \
  mcr.microsoft.com/mssql/server:2022-latest
```

# 已在跑的容器（進去修權限）

```bash
# 以 root 進容器
docker exec -u 0 -it mssql2022 bash

# 修正 /var/opt/mssql 及自訂路徑擁有者與權限
chown -R 10001:0 /var/opt/mssql /vol2/1000/ssd/app-data/mssql2022
chmod -R 770 /var/opt/mssql /vol2/1000/ssd/app-data/mssql2022

exit
docker restart mssql2022
```

# 驗證

```bash
# 目錄與權限
ls -ld /vol2/1000/ssd/app-data/mssql2022
ls -ld /vol2/1000/ssd/app-data/mssql2022/{data,log,backup}

# 看到類似 drwxrwx--- 10001 0 即正確
```



