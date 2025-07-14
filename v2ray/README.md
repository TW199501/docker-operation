#### 安裝V2ray
'''

'''

#### UUID產生器

'''
https://www.uuidgenerator.net/
'''



#### 安裝V2ray中的Groip資料庫

```
mkdir -p /usr/local/share/v2ray

cd /usr/local/share/v2ray

wget https://github.com/v2fly/geoip/releases/latest/download/geoip.dat

wget https://github.com/v2fly/domain-list-community/releases/latest/download/geosite.dat

ln -s /usr/local/share/v2ray/geoip.dat /usr/bin/geoip.dat

ln -s /usr/local/share/v2ray/geosite.dat /usr/bin/geosite.dat
```

#### 重新啟動v2ray
```
systemctl restart v2ray

systemctl status v2ray

systemctl enable v2ray
```

#### 調整ulimit：增加最大連線數（ulimit -n 65535
```
# 修改 /etc/security/limits.conf 文件，加入：
* soft nofile 65535
* hard nofile 65535
# 編輯服務單元檔/lib/systemd/system/v2ray.service），在 [Service] 段落加上：
LimitNOFILE=65535

#重新加載 systemd 配置與重啟服務：
systemctl daemon-reload
systemctl restart v2ray
```
