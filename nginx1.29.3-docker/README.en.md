# Elf-Nginx Containerized Deployment Solution

> 📚 **Complete documentation available in [`docs/`](docs/) directory**

Elf-Nginx is an enterprise-grade containerized deployment solution based on Nginx 1.29.3. It integrates high availability, security protection, geolocation recognition, and automated operations.

## 🚀 Key Features

- **High Performance**: Custom-compiled from source with multiple performance-oriented modules.
- **High Availability**: Keepalived-based active/standby failover.
- **Security Protection**: Multiple layers including ModSecurity WAF, GeoIP, and IP filtering.
- **Automation**: Scheduled updates of GeoIP databases and Cloudflare configuration.
- **Modular Design**: Dynamic module loading with flexible configuration management.

### 🔗 Quick Navigation

- 📖 [Project Overview](docs/README.en.md) - Basic introduction and feature overview
- 🚀 [Quick Start](docs/deployment-guide.md#quick-start) - 5-minute deployment guide
- ⚙️ [Configuration](docs/configuration.md) - Complete configuration guide
- 🌐 [Network Guide](docs/network-guide.md) - Docker network configuration tutorial
- 🔧 [Deployment Guide](docs/deployment-guide.md) - Detailed deployment workflow
- 🐛 [Troubleshooting](docs/troubleshooting.md) - Common issues and solutions
- 🛠️ [Development Guide](docs/development.md) - Development and maintenance

### ⚡ Quick Start

```bash
# 1. Build container images
cd nginx1.29.3-docker
docker compose -f docker-compose.build.yml build

# 2. Start services
docker compose -f docker-compose.build.yml up -d --build

# 3. Check status
docker compose ps
```

### 🏗️ Technical Architecture

#### Core Components

| Component | Version | Description |
|-----------|---------|-------------|
| Nginx | 1.29.3 | Custom compiled with performance modules |
| HAProxy | trixie | Load balancing and traffic forwarding |
| Keepalived | 2.3.4 | High availability failover |
| ModSecurity | v3 | WAF security protection |

#### Integrated Modules

| Module | Description |
|--------|-------------|
| ngx_http_geoip2_module | GeoIP2 geolocation |
| ngx_brotli | Google Brotli compression |
| headers-more-nginx-module | Custom HTTP headers |
| ngx_cache_purge | Cache purge functionality |
| njs | JavaScript support |
| ModSecurity-nginx | WAF security |

#### Dependency Versions

- **OpenSSL**: 3.5.4
- **PCRE2**: 10.47
- **zlib**: 1.3.1
- **libmaxminddb**: 1.12.2

## 📁 Project Structure

```text
nginx1.29.3-docker/
├── Dockerfile                     # Container build configuration
├── docker-compose.yml             # Runtime compose (elf-nginx + haproxy)
├── docker-compose.build.yml       # Build-time compose (build & test images)
├── build-nginx.sh                 # Nginx build script
├── 30-keepalived-install.sh       # Keepalived install script for bare metal / VMs
├── keepalived-install.sh          # Lightweight Keepalived install script
├── docker-entrypoint.sh           # Nginx container entrypoint
├── nginx/                         # Nginx config & data mount root
│   ├── etc/                       # Nginx configuration
│   ├── modules/                   # Dynamic modules
│   ├── logs/                      # Runtime logs
│   ├── cache/                     # Cache files
│   ├── geoip/                     # GeoIP databases
│   └── keepalived/                # Keepalived config (mount only)
├── haproxy/
│   └── haproxy.cfg                # HAProxy frontend config
├── README.md                      # Chinese documentation
├── README.en.md                   # English documentation (this file)
└── todos.md                       # Development task list
```

## 🔧 Configuration Details

### Docker Compose Configuration (runtime example)

```yaml
version: "3.9"

services:
  elf-nginx:
    container_name: elf-nginx
    build:
      context: .
      dockerfile: Dockerfile        # Build from the Dockerfile in this directory
    image: elf-nginx:latest
    restart: unless-stopped
    volumes:
      - ./nginx/etc:/etc/nginx                      # Persist configuration
      - ./nginx/modules:/usr/lib/nginx/modules      # Dynamic modules
      - ./nginx/logs:/var/log/nginx                 # Persist logs
      - ./nginx/cache:/var/cache/nginx              # Persist cache
      - ./nginx/geoip:/usr/share/GeoIP              # GeoIP databases
      - ./nginx/keepalived:/etc/keepalived          # Keepalived config (mount only)

  haproxy:
    container_name: haproxy
    image: haproxy:2.9
    restart: unless-stopped
    depends_on:
      - elf-nginx
    ports:
      - "80:80"    # HTTP traffic
      - "443:443"  # HTTPS traffic
    volumes:
      - ./haproxy/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro
```

> Note: The actual production runtime now uses `docker-compose.yml`, `docker-compose.build.yml`, and `nginx-ui-compose.yml` together. See the **Deployment Guide** section for the latest recommended flow.

### Nginx Configuration Layout

```text
/etc/nginx/
├── nginx.conf                    # Main configuration
├── modules.conf                  # Dynamic module loading
├── conf.d/                       # Generic config snippets
│   ├── ssl.conf                  # SSL/TLS config
│   ├── cloudflare.conf           # Cloudflare integration
│   └── waf.conf                  # WAF rules
├── sites-available/              # Available site configs
│   └── default.conf              # Default site
├── sites-enabled/                # Enabled site configs
│   └── default.conf -> ../sites-available/default.conf
├── geoip/                        # Geolocation/IP settings
│   ├── cloudflare_v4_realip.conf
│   ├── cloudflare_v6_realip.conf
│   ├── ip_whitelist.conf        # IP whitelist
│   └── ip_blacklist.conf        # IP blacklist
└── scripts/                      # Management scripts
    ├── update_geoip.sh          # GeoIP update script
    └── manage_ip.sh             # IP management tool
```

### SSL/TLS Security Configuration

```nginx
# SSL settings
ssl_protocols TLSv1.2 TLSv1.3;
ssl_prefer_server_ciphers on;
ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384';
ssl_session_cache shared:SSL:10m;
ssl_session_timeout 10m;
```

## 🛡️ Security Features

### 1. ModSecurity WAF

- Integrated **OWASP Core Rule Set (CRS)**.
- **Dynamic rule loading** mechanism.
- **JSON-format audit logs**.
- Support for **custom exception rules**.

### 2. GeoIP-based Filtering

- Real-time geolocation detection.
- Country/city-level resolution.
- Scheduled database updates.
- Cloudflare IP range integration.

### 3. Access Control

- **IP whitelist** – allow-only trusted IPs/subnets.
- **IP blacklist** – block suspicious IPs/subnets.
- **Dynamic rule management** – adjust at runtime.

## 🚀 High Availability Configuration

### Keepalived Setup

#### Example Configuration

```ini
global_defs {
    enable_script_security
    script_user root
}

vrrp_script chk_nginx {
    script "/usr/local/sbin/check_nginx.sh"
    interval 2
    fall 3
    rise 2
}

vrrp_instance VI_51 {
    state MASTER                    # MASTER or BACKUP
    interface eth0                  # Network interface
    virtual_router_id 51            # VRRP group ID
    priority 200                    # Priority (MASTER: 200, BACKUP: 100)
    advert_int 1                    # Advertisement interval (seconds)

    # Unicast configuration
    unicast_src_ip 192.168.25.10    # Local IP
    unicast_peer {
        192.168.25.11               # Peer IP
    }

    authentication {
        auth_type PASS
        auth_pass 23887711          # VRRP authentication password
    }

    track_script {
        chk_nginx                   # Health check script
    }

    virtual_ipaddress {
        192.168.25.250/24 dev eth0  # Virtual IP
    }
}
```

#### Health Check Mechanism

- **Process check** – monitor the main Nginx process.
- **Service response** – optional HTTP health checks.
- **Automatic failover** – switch to backup on failure.

## 📊 Performance Optimization

### Compression

- **Gzip** – standard HTTP compression.
- **Brotli** – efficient compression from Google.
- **Static file optimization** – support precompressed assets.

### Caching

- **Proxy cache** – cache upstream responses.
- **Client cache** – browser-side cache control.
- **FastCGI cache** – cache dynamic content.

### HTTP/2 & HTTP/3

- **HTTP/2 multiplexing** – faster page loads.
- **HTTP/3 QUIC** – latest protocol support.

## 🔄 Automated Operations

### Scheduled Tasks

#### GeoIP Database Updates

- **Schedule**: Every Wednesday and Saturday at 03:00.
- **Content**: GeoLite2 Country/City/ASN databases.
- **Scope**: Cloudflare IP ranges.
- **Automation**: Auto restart/reload Nginx after updates.

#### Systemd Timer Example

```bash
# systemd timer example
[Timer]
OnCalendar=Wed,Sat 03:00
Persistent=true
RandomizedDelaySec=5min
```

### Log Management

- **Access log** – `/var/log/nginx/access.log`
- **Error log** – `/var/log/nginx/error.log`
- **WAF audit log** – `/var/log/modsecurity/audit.log`
- **Keepalived log** – `/var/log/keepalived/`

## 🏃‍♂️ Deployment Guide

### Environment Requirements

- **Docker**: 20.10+
- **Docker Compose**: 2.0+
- **System Resources**: Minimum 2 GB RAM, 4 GB disk.
- **Network**: Able to expose ports 80/443.

### Quick Start (Local Development)

#### 1. Build Images

```bash
# From the project root (the folder that contains nginx1.29.3-docker/)
 docker builder prune -f    # Optional: clean up build cache

 cd nginx1.29.3-docker
 docker compose -f docker-compose.build.yml build
```

#### 2. Start Local Services (Testing)

```bash
# Start elf-nginx + haproxy using the build compose file
 docker compose -f docker-compose.build.yml up -d --build
```

#### 3. Push Images to Docker Hub

```bash
 docker login
 docker push tw199501/nginx:1.29.3
 docker push tw199501/haproxy:trixie

 # Optionally, use the provided helper scripts:
 # Bash (Git Bash / WSL):
 #   bash nginx1.29.3-docker/push-images.sh
 # Windows PowerShell (from project root):
 #   .\nginx1.29.3-docker\push-images.ps1
```

### Cross-Host Deployment (VM / Bare Metal)

#### 1. Prepare Directories on Target Host

```bash
sudo mkdir -p /opt/nginx-stack/nginx
sudo mkdir -p /opt/nginx-stack/nginx-ui
```

#### 2. Pull Images on Target Host

```bash
docker pull tw199501/nginx:1.29.3
docker pull tw199501/haproxy:trixie
```

#### 3. Start Services Using Compose

> Copy the release-time `docker-compose.yml` and `nginx-ui-compose.yml` to the same directory on the target host.

```bash
docker compose -f docker-compose.yml up -d
docker compose -f nginx-ui-compose.yml up -d
```

#### 4. Manage Configuration via Nginx UI (Plan B)

```text
Traffic path:  Client -> haproxy(80/443) -> elf-nginx:80
Config path:   /opt/nginx-stack/nginx      <-> elf-nginx:/etc/nginx
               /opt/nginx-stack/nginx      <-> nginx-ui:/etc/nginx
               /opt/nginx-stack/nginx-ui   <-> nginx-ui:/etc/nginx-ui
```

- Access Nginx UI for the first time at:
  - `http://<host>:8080` or
  - `https://<host>:8443`

### High Availability Deployment

#### 1. Primary/Backup Node Variables

```bash
# Primary node (MASTER)
export ROLE=MASTER
export IFACE=eth0
export VRID=51
export VIP_CIDR=192.168.25.250/24
export PEER_IP=192.168.25.11
export PRIORITY=200

# Backup node (BACKUP)
export ROLE=BACKUP
export IFACE=eth0
export VRID=51
export VIP_CIDR=192.168.25.250/24
export PEER_IP=192.168.25.10
export PRIORITY=100
```

#### 2. Run Keepalived Installer

```bash
# Run on both nodes
bash 30-keepalived-install.sh
```

#### 3. Validate High Availability

```bash
# Check virtual IP binding
ip -4 addr show dev eth0 | grep 192.168.25.250

# Inspect VRRP status
journalctl -u keepalived -e -n 50
```

## 🔧 Management Commands

### IP Management Tool

```bash
# Add IP to whitelist
bash /etc/nginx/scripts/manage_ip.sh allow 192.168.1.100 /etc/nginx/geoip/ip_whitelist.conf

# Remove IP from whitelist
bash /etc/nginx/scripts/manage_ip.sh deny 192.168.1.100 /etc/nginx/geoip/ip_whitelist.conf
```

### Service Management

```bash
# Reload Nginx configuration
nginx -s reload

# Test Nginx configuration
nginx -t

# Restart Nginx service
systemctl restart nginx

# Check Nginx status
systemctl status nginx
```

### Monitoring & Maintenance

```bash
# List Nginx processes
ps aux | grep nginx

# Check port usage
netstat -tlnp | grep :80
netstat -tlnp | grep :443

# Tail logs
```

```bash
tail -f /var/log/nginx/access.log
tail -f /var/log/nginx/error.log
```

## 🚨 Troubleshooting

### Common Issues

#### 1. Container Fails to Start

```bash
# Check container logs
docker-compose logs elf-nginx

# Check port conflicts
netstat -tlnp | grep :80
netstat -tlnp | grep :443
```

#### 2. Nginx Configuration Errors

```bash
# Test configuration syntax
docker exec elf-nginx nginx -t

# Inspect config file
docker exec elf-nginx cat /etc/nginx/nginx.conf
```

#### 3. Keepalived Failover Problems

```bash
# Check VRRP status
journalctl -u keepalived --no-pager

# Validate health check script
bash /usr/local/sbin/check_nginx.sh
```

### Log Analysis

#### Key Log Paths

- **Nginx error log**: `/var/log/nginx/error.log`
- **WAF audit log**: `/var/log/modsecurity/audit.log`
- **Keepalived logs**: `journalctl -u keepalived`

## 📈 Performance Tuning

### System Parameter Tuning

```bash
# File descriptor limits
echo "nginx soft nofile 65535" >> /etc/security/limits.conf
echo "nginx hard nofile 65535" >> /etc/security/limits.conf

# Network tuning
echo "net.core.somaxconn = 65535" >> /etc/sysctl.conf
sysctl -p
```

### Nginx Worker Tuning

```nginx
worker_processes auto;
worker_connections 4096;
worker_rlimit_nofile 65535;
```

## 🔐 Security Recommendations

### 1. Regular Updates

- **Security patches** – keep OS and packages updated.
- **SSL certificates** – use Let's Encrypt with auto renewal.
- **WAF rules** – update rule sets regularly.

### 2. Access Control

- **Whitelisting** – allow only trusted IP ranges.
- **Rate limiting** – mitigate DDoS.
- **Strong SSL config** – follow modern cipher suites.

### 3. Monitoring & Alerting

- **Log monitoring** – alert on abnormal access.
- **Performance monitoring** – track latency and throughput.
- **Security monitoring** – detect suspicious patterns.

## 📦 Docker / Compose Cheat Sheet

> The commands below assume you are in the `nginx1.29.3-docker` directory.

```bash
# Build images using the build compose file (build only)
docker compose -f docker-compose.build.yml build

# Build and start containers (dev use)
docker compose -f docker-compose.build.yml up -d --build

# Start services using the release docker-compose.yml (for consumers of the images)
docker compose up -d

# Stop and remove containers (keep images)
docker compose down

# Show current container status
docker compose ps

# Tail logs for nginx / haproxy
docker compose logs -f elf-nginx
docker compose logs -f haproxy

# Enter nginx container (debugging)
docker exec -it elf-nginx /bin/bash

# Manually trigger GeoIP update script
docker exec elf-nginx /etc/nginx/scripts/update_geoip.sh
```

## 📞 Support & Project Info

### Related Documentation

- [Nginx Official Docs](https://nginx.org/en/docs/)
- [ModSecurity Documentation](https://github.com/SpiderLabs/ModSecurity/wiki)
- [Keepalived Documentation](https://keepalived.readthedocs.io/)

### Project Information

- **Version**: 1.29.3
- **Last Updated**: 2025-11-28
- **Maintainer**: Elf team

---

*This project aims to provide an enterprise-grade containerized Nginx solution. Issues and pull requests are welcome.*
