## Proxmox8.0-9.0 VM 虛擬機自動化腳本

### Debain 13 

1.下載安裝腳本
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/TW199501/docker-operation/main/proxmox9.0/debian13-vm.sh)"
```
2. 執行安裝SSH
```bash
sudo apt update && sudo apt install -y openssh-client openssh-server
passwd root
sed -i -e 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/g' -e 's/^PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
ssh-keygen -A
systemctl restart sshd
```

