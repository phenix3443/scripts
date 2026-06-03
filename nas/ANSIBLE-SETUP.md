# NAS Ansible 自动化部署指南

使用 Ansible 自动化部署 OpenMediaVault 到树莓派 5 + 三星 970 EVO 1TB NVMe SSD。

## 快速开始（5 分钟配置，30 分钟部署）

### 1. 准备硬件

- ✅ 树莓派 5 (8GB)
- ✅ 三星 970 EVO 1TB NVMe SSD
- ✅ PCIe 扩展板（支持 2280 尺寸）
- ✅ 官方 27W USB-C 电源
- ✅ 主动散热器

### 2. 烧录系统（5 分钟）

使用 Raspberry Pi Imager：

1. OS: Raspberry Pi OS (other) → Raspberry Pi OS Lite (64-bit)
2. 存储设备: 三星 970 EVO（通过 USB 转接器连接到电脑）
3. 高级设置（⚙️ 图标）：
   - 主机名: `nas1`
   - 用户名: `lsl`（或你的用户名）
   - 密码: 设置一个强密码
   - WiFi: 配置你的 WiFi（如果使用有线可跳过）
   - SSH: 启用（使用密码或公钥认证）
   - 时区: `Asia/Shanghai`
4. 烧录完成后，将 SSD 装回树莓派 5
5. 启动树莓派，等待 2-3 分钟

### 3. 配置 Ansible（2 分钟）

在你的电脑上：

```bash
# 克隆仓库（如果还没有）
git clone https://github.com/womenlia/home-lab.git
cd home-lab

# 安装 Ansible
pip3 install ansible

# 查找树莓派 IP（如果不知道）
# 方法 1: 路由器管理界面查看
# 方法 2: 使用 nmap
# nmap -sn 192.168.1.0/24 | grep -B 2 "Raspberry"

# 测试 SSH 连接
ssh lsl@<树莓派IP>
# 成功登录后退出
exit
```

### 4. 配置 Inventory（1 分钟）

```bash
# 编辑 inventory 文件
vim ansible/inventory/nas.yml
```

修改以下内容：

```yaml
nas1:
  ansible_host: 192.168.1.100  # 改为你的树莓派 IP
  ansible_user: lsl             # 改为你的用户名
  nvme_device: /dev/nvme0n1     # NVMe 设备路径（通常不需要改）
```

### 5. 配置 Vault（1 分钟，可选）

如果需要 Cloudflare Tunnel 远程访问：

```bash
# 创建 vault 密码文件
echo "my-secure-password" > ansible/.vault_pass
chmod 600 ansible/.vault_pass

# 复制并编辑 vault 文件
cp ansible/group_vars/nas_servers/vault.yml.example \
   ansible/group_vars/nas_servers/vault.yml

# 编辑 vault.yml，填入你的 Cloudflare Tunnel token
vim ansible/group_vars/nas_servers/vault.yml

# 加密 vault 文件
ansible-vault encrypt ansible/group_vars/nas_servers/vault.yml \
  --vault-password-file ansible/.vault_pass
```

### 6. 一键部署（30 分钟）

```bash
# 运行快速开始脚本
./ansible/scripts/nas-quick-start.sh

# 或者手动执行
ansible-playbook -i ansible/inventory/nas.yml \
  ansible/playbooks/nas/0-omv-install.yml \
  --vault-password-file ansible/.vault_pass \
  --ask-become-pass
```

### 7. 访问 OMV

部署完成后：

- **本地访问**: `http://<树莓派IP>`
- **默认登录**: `admin` / `openmediavault`
- **⚠️ 立即修改默认密码！**

## 部署内容

### Stage 0: 安装 OMV（20-40 分钟）

自动完成：
- ✅ 系统更新和升级
- ✅ 安装基础包（curl, git, vim, htop, smartmontools, nvme-cli）
- ✅ 配置时区和 NTP
- ✅ 优化 NVMe 设置（电源管理、I/O 调度器、TRIM）
- ✅ 安装 OpenMediaVault 8.x
- ✅ 配置 passwordless sudo

### Stage 1: 配置监控（2-5 分钟）

自动完成：
- ✅ NVMe 温度监控（每 10 分钟）
- ✅ 系统健康检查（每小时）
- ✅ 磁盘空间监控
- ✅ 服务状态监控
- ✅ SMART 健康检查
- ✅ 日志轮转配置
- ✅ 状态仪表板脚本

### Stage 2: Cloudflare Tunnel（2-3 分钟，可选）

自动完成：
- ✅ 安装 cloudflared
- ✅ 配置 tunnel 服务
- ✅ 启用自动启动

## 验证部署

### 检查 OMV 服务

```bash
# SSH 登录
ssh lsl@<树莓派IP>

# 查看状态仪表板
sudo /usr/local/bin/nas-status.sh
```

输出示例：

```
==========================================
NAS Status Dashboard
==========================================

CPU Temperature:
temp=45.0'C

NVMe Temperature:
temperature                         : 42 C

NVMe Health:
SMART overall-health self-assessment test result: PASSED

NVMe Wear Level:
percentage_used                     : 5%

Disk Usage:
/dev/nvme0n1p2  916G   15G  855G   2% /

OMV Service Status:
Active: active (running)

Memory Usage:
              total        used        free      shared  buff/cache   available
Mem:          7.8Gi       1.2Gi       5.9Gi        50Mi       702Mi       6.4Gi

Uptime:
 10:30:15 up 2 days,  3:45,  1 user,  load average: 0.15, 0.20, 0.18

==========================================
```

### 检查监控定时器

```bash
# 查看定时器状态
systemctl list-timers | grep nas

# 查看监控日志
tail -f /var/log/nvme-temp.log
tail -f /var/log/nas-health.log
```

### 检查 Cloudflare Tunnel

```bash
# 查看服务状态
sudo systemctl status cloudflared

# 查看连接日志
sudo journalctl -u cloudflared -f
```

## 常见问题

### Q1: Ansible 连接失败

```bash
# 错误: Permission denied (publickey,password)
# 解决: 添加 --ask-pass 参数
ansible-playbook -i ansible/inventory/nas.yml \
  ansible/playbooks/nas/0-omv-install.yml \
  --ask-pass --ask-become-pass
```

### Q2: NVMe 无法识别

```bash
# SSH 登录检查
ssh lsl@<树莓派IP>

# 检查 NVMe 设备
lsblk
nvme list

# 如果没有输出，检查硬件连接
# 1. 扩展板是否正确连接
# 2. FPC 软排线是否插紧
# 3. 重新插拔后重启
```

### Q3: OMV 安装超时

```bash
# 增加超时时间
ansible-playbook -i ansible/inventory/nas.yml \
  ansible/playbooks/nas/0-omv-install.yml \
  --vault-password-file ansible/.vault_pass \
  --ask-become-pass \
  -e "ansible_command_timeout=7200"
```

### Q4: Web 界面无法访问

```bash
# 检查服务状态
sudo systemctl status openmediavault-engined
sudo systemctl status nginx

# 检查端口监听
sudo ss -tlnp | grep :80

# 重启服务
sudo systemctl restart openmediavault-engined
sudo systemctl restart nginx
```

## 性能优化

### 启用 PCIe Gen 3（实验性）

```bash
# SSH 登录
ssh lsl@<树莓派IP>

# 编辑 config.txt
sudo nano /boot/firmware/config.txt

# 添加以下行
dtparam=pciex1_gen=3

# 保存并重启
sudo reboot

# 测试速度
sudo hdparm -t /dev/nvme0n1
```

### 性能基准测试

```bash
# 安装测试工具
sudo apt install fio -y

# 顺序读测试
sudo fio --name=seqread --rw=read --bs=1M --size=1G \
  --numjobs=1 --filename=/tmp/testfile

# 预期结果: 400-500 MB/s
```

## 下一步

1. **修改默认密码**
   - 登录 OMV: `http://<树莓派IP>`
   - System → General Settings → Web Administrator Password

2. **配置存储**
   - Storage → File Systems → 挂载数据分区
   - Storage → Shared Folders → 创建共享文件夹

3. **启用文件共享**
   - Services → SMB/CIFS → 启用并配置
   - Services → NFS → 启用并配置（可选）

4. **配置 Cloudflare Tunnel 公网访问**
   - 登录 [Cloudflare Zero Trust](https://one.dash.cloudflare.com/)
   - Networks → Tunnels → 选择你的 tunnel
   - Configure → Public Hostnames → Add
   - Subdomain: `nas`, Domain: `yourdomain.com`, Service: `http://localhost:80`
   - 访问: `https://nas.yourdomain.com`

5. **部署 Nextcloud**（可选）
   - 参考 `nas/omv/01-替代网盘/` 目录
   - 使用 Docker Compose 部署

6. **配置备份**
   - 设置定期备份到外部存储
   - 配置云存储同步（rclone）

## 维护命令

```bash
# 查看 NAS 状态
ansible -i ansible/inventory/nas.yml nas_servers -m shell \
  -a "sudo /usr/local/bin/nas-status.sh"

# 更新系统
ansible -i ansible/inventory/nas.yml nas_servers -m shell \
  -a "sudo apt update && sudo apt upgrade -y" --become

# 重启 NAS
ansible -i ansible/inventory/nas.yml nas_servers -m reboot --become

# 备份 OMV 配置
ansible -i ansible/inventory/nas.yml nas_servers -m shell \
  -a "sudo omv-backup /tmp/omv-backup-$(date +%Y%m%d).tar.gz" --become
```

## 参考文档

- [完整 NAS 方案文档](plan.md)
- [Ansible Playbook 详细说明](../ansible/README-NAS.md)
- [OMV 替代网盘方案](omv/01-替代网盘/)
- [OpenMediaVault 官方文档](https://docs.openmediavault.org/)
- [树莓派 5 文档](https://www.raspberrypi.com/documentation/computers/raspberry-pi-5.html)

## 故障排查

如遇到问题，请查看：
1. [Ansible README-NAS.md 常见问题](../ansible/README-NAS.md#常见问题)
2. [NAS plan.md 故障排查](plan.md#故障排查)
3. 或在 GitHub 提 Issue
