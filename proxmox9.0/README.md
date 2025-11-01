## Proxmox VE 虛擬機自動化腳本

### Debain 13 

下載安裝腳本
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/TW199501/docker-operation/main/proxmox9.0/debian13-vm.sh)"
```
2. 執行安裝SSH
```bash
apt install openssh-client
apt install openssh-server
passwd root
sed -i -e 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/g' -e 's/^PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
ssh-keygen -A
systemctl restart sshd
```