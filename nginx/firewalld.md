```

bash -c "$(curl -fsSL https://raw.githubusercontent.com/TW199501/docker-operation/main/nginx/00-preflight-nginx.sh)"
bash -c "$(curl -fsSL https://raw.githubusercontent.com/TW199501/docker-operation/main/nginx/10-build-nginx.sh)"
bash -c "$(curl -fsSL https://raw.githubusercontent.com/TW199501/docker-operation/main/nginx/15-modsecurity-nginx.sh)"
bash -c "$(curl -fsSL https://raw.githubusercontent.com/TW199501/docker-operation/main/nginx/30-keepalived-install.sh)"
bash -c "$(curl -fsSL https://raw.githubusercontent.com/TW199501/docker-operation/main/nginx/update_geoip2_cf_ip..sh)"
```

# 安裝並啟用

```
sudo dnf install -y firewalld
sudo systemctl enable --now firewalld
```

# 1) 建立 Cloudflare 的 ipset（若已存在不會影響）

```
sudo firewall-cmd --permanent --new-ipset=cloudflare4 --type=hash:net 2>/dev/null || true
sudo firewall-cmd --permanent --new-ipset=cloudflare6 --type=hash:net 2>/dev/null || true
```

# 2) 匯入 Cloudflare 官方 IPv4/IPv6 清單

```
curl -fsS https://www.cloudflare.com/ips-v4 | sudo xargs -I{} firewall-cmd --permanent --ipset=cloudflare4 --add-entry={}
curl -fsS https://www.cloudflare.com/ips-v6 | sudo xargs -I{} firewall-cmd --permanent --ipset=cloudflare6 --add-entry={}
```

# 3) 只允許 Cloudflare 來源打 80/443（其餘來源拒絕）

```
sudo firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source ipset="cloudflare4" port port="80"  protocol="tcp" accept'
sudo firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source ipset="cloudflare4" port port="443" protocol="tcp" accept'
sudo firewall-cmd --permanent --add-rich-rule='rule family=ipv6 source ipset="cloudflare6" port port="80"  protocol="tcp" accept'
sudo firewall-cmd --permanent --add-rich-rule='rule family=ipv6 source ipset="cloudflare6" port port="443" protocol="tcp" accept'
```

# 4) 內網允許 22/8080（只限 192.168.25.0/24）

```
sudo firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address="192.168.25.0/24" port port="22"   protocol="tcp" accept'
sudo firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address="192.168.25.0/24" port port="8080" protocol="tcp" accept'
```

# 5) 確保沒把 80/443/22/8080 全網打開（移除曾經加過的服務/埠）

```
sudo firewall-cmd --permanent --remove-service=http  2>/dev/null || true
sudo firewall-cmd --permanent --remove-service=https 2>/dev/null || true
sudo firewall-cmd --permanent --remove-service=ssh   2>/dev/null || true
sudo firewall-cmd --permanent --remove-port=8080/tcp 2>/dev/null || true
```

# 6) 套用

```
sudo firewall-cmd --reload
```

# 7) 檢查

```
sudo firewall-cmd --list-rich-rules
sudo firewall-cmd --info-ipset=cloudflare4 | sed -n '1,10p'
```
