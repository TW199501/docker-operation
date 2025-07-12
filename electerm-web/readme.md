#### 這是一款web-ssh

步驟一
mkdir -p /mnt/Storage/app/electerm-web/users/default_user
步驟二
id -u  # 取得 UID
id -g  # 取得 GID

步驟三
chown -R  999:999 /mnt/Storage/app/electerm-web/users
chmod -R 750  /mnt/Storage/app/electerm-web/users


