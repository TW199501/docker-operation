```
sudo mkdir -p /etc/docker

sudo tee /etc/docker/daemon.json << 'EOF'
{
  "dns": ["1.1.1.1", "168.95.1.1", "8.8.8.8"] 
}
EOF
```
