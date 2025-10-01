安裝keepalived
- 在主節點 A 跑（把參數換成你的實際值）：

```
sudo bash keepalived-install.sh \
  --iface=eth0 --src-ip=192.168.25.24 --peer-ip=192.168.25.25 \
  --vip=192.168.25.26/24 --vrid=26 --state=MASTER --priority=150
```

- 在備份節點 B 跑（把參數換成你的實際值）：

```
sudo bash keepalived-install.sh \
  --iface=eth0 --src-ip=192.168.25.25 --peer-ip=192.168.25.24 \
  --vip=192.168.25.26/24 --vrid=26 --state=BACKUP --priority=100
```
