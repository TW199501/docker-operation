#### 這是一款web-ssh
步驟一
id -u  # 取得 UID
id -g  # 取得 GID

步驟二
chown -R  999:999 - /mnt/Storage/app/electerm-web/users
chmod -R 700    /vol2/1000/hd-app/electerm-web/users

