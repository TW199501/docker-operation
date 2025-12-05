# Elf-Nginx Containerized Deployment Solution

## 📖 Project Overview

Elf-Nginx is an enterprise-grade containerized deployment solution based on Nginx 1.29.3. It integrates high availability, security protection, geolocation recognition, and automated operations.

### 🚀 Key Features

- **High Performance**: Custom-compiled from source with multiple performance-oriented modules.
- **High Availability**: Keepalived-based active/standby failover.
- **Security Protection**: Multiple layers including ModSecurity WAF, GeoIP, and IP filtering.
- **Automation**: Scheduled updates of GeoIP databases and Cloudflare configuration.
- **Modular Design**: Dynamic module loading with flexible configuration management.

## 🏗️ Technical Architecture

### Core Components

#### Web Server

- **Nginx Version**: 1.29.3 (custom compiled)
- **Base Image**: Debian Bookworm Slim
- **Build Options**: Full feature set including SSL, HTTP/2, and HTTP/3.

#### Integrated Third-Party Modules

| Module | Description | Version |
|--------|-------------|---------|
| ngx_http_geoip2_module | GeoIP2 geolocation | latest |
| ngx_brotli | Google Brotli compression | latest |
| headers-more-nginx-module | Custom HTTP headers | latest |
| ngx_cache_purge | Cache purge | latest |
| njs | JavaScript support | latest |
| ModSecurity-nginx | WAF security | v1.0.4 |

#### Dependency Versions

- **OpenSSL**: 3.5.4
- **PCRE2**: 10.47
- **zlib**: 1.3.1
- **libmaxminddb**: 1.12.2

## 🚀 Quick Start

### Environment Requirements

- **Docker**: 20.10+
- **Docker Compose**: 2.0+
- **System Resources**: Minimum 2 GB RAM, 4 GB disk.
- **Network**: Able to expose ports 80/443.

### Quick Deployment

```bash
# Build container images
cd nginx1.29.3-docker
docker compose -f docker-compose.build.yml build

# Start services
docker compose -f docker-compose.build.yml up -d --build

# Check service status
docker compose ps
```

## 📁 Documentation Structure

- [README.md](./README.md) - Project overview and quick start
- [README.en.md](./README.en.md) - English version
- [deployment-guide.md](./deployment-guide.md) - Detailed deployment guide
- [configuration.md](./configuration.md) - Configuration details
- [network-guide.md](./network-guide.md) - Network configuration tutorial
- [troubleshooting.md](./troubleshooting.md) - Troubleshooting guide
- [development.md](./development.md) - Development and maintenance

## 🛠️ Key Features

### 1. Containerized Deployment

- Complete Docker-based containerized solution
- Multi-environment deployment support (dev, test, prod)
- Automated build and deployment workflows

### 2. High Availability

- Keepalived-based master-slave failover
- Health check mechanisms
- Automatic fault recovery

### 3. Security Protection

- ModSecurity WAF integration
- GeoIP geolocation filtering
- IP whitelist/blacklist management
- Strong SSL/TLS encryption configuration

### 4. Automated Operations

- Regular GeoIP database updates
- Cloudflare IP range synchronization
- Automated log management
- System monitoring and alerting

## 📞 Support & Project Info

### Related Documentation

- [Nginx Official Docs](https://nginx.org/en/docs/)
- [ModSecurity Documentation](https://github.com/SpiderLabs/ModSecurity/wiki)
- [Keepalived Documentation](https://keepalived.readthedocs.io/)

### Project Information

- **Version**: 1.29.3
- **Last Updated**: 2025-12-05
- **Maintainer**: Elf team

---

*This project aims to provide an enterprise-grade containerized Nginx solution. Issues and pull requests are welcome.*
