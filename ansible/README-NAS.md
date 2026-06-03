# NAS (OpenMediaVault) Ansible Playbooks

基于 Ansible 自动化部署 OpenMediaVault NAS 系统到树莓派 5 + NVMe SSD。

## 硬件要求

- Raspberry Pi 5 (8GB 推荐)
- NVMe SSD (通过 PCIe 扩展板连接)
- 官方 27W USB-C 电源
- 主动散热器
- 已安装 Raspberry Pi OS Lite (64-bit) 基于 Debian 13 "Trixie"

## 前置准备

### 1. 安装基础系统

使用 Raspberry Pi Imager 将 Raspberry Pi OS Lite (64-bit) 烧录到 NVMe SSD：

1. 选择 OS：Raspberry Pi OS (other) → Raspberry Pi OS Lite (64-bit)
2. 选择存储设备：你的 NVMe SSD（通过 USB 转接器连接到电脑）
3. 配置高级选项（齿轮图标）：
   - 设置主机名（如 `nas1`）
   - 启用 SSH（使用密码或公钥认证）
   - 设置用户名和密码
   - 配置 WiFi（如果需要）
   - 设置时区：Asia/Shanghai

4. 烧录完成后，将 NVMe SSD 装回树莓派 5 的 PCIe 扩展板
5. 启动树莓派 5，等待系统启动完成

### 2. 配置 Ansible 控制机

在你的控制机（笔记本/台式机）上：

```bash
# 安装 Ansible
pip3 install ansible

# 克隆仓库
git clone https://github.com/womenlia/home-lab.git
cd home-lab

# 创建 vault 密码文件
echo "your-vault-password" > ansible/.vault_pass
chmod 600 ansible/.vault_pass
```

### 3. 配置 Inventory

编辑 `ansible/inventory/nas.yml`，更新以下内容：

```yaml
nas1:
  ansible_host: 192.168.1.100  # 替换为你的树莓派 IP
  ansible_user: lsl             # 替换为你的用户名
  nvme_device: /dev/nvme0n1     # NVMe 设备路径
```

### 4. 配置 Vault 变量

```bash
# 复制示例文件
cp ansible/group_vars/nas_servers/vault.yml.example \
   ansible/group_vars/nas_servers/vault.yml

# 编辑 vault.yml，填入你的 Cloudflare Tunnel token
vim ansible/group_vars/nas_servers/vault.yml

# 加密 vault 文件
ansible-vault encrypt ansible/group_vars/nas_servers/vault.yml \
  --vault-password-file ansible/.vault_pass
```

### 5. 测试连接

```bash
# 测试 SSH 连接
ansible -i ansible/inventory/nas.yml nas_servers -m ping

# 如果提示输入密码，添加 --ask-pass
ansible -i ansible/inventory/nas.yml nas_servers -m ping --ask-pass
```

## 部署步骤

### Stage 0: 安装 OpenMediaVault

```bash
# 首次运行需要输入 sudo 密码
ansible-playbook -i ansible/inventory/nas.yml \
  ansible/playbooks/nas/0-omv-install.yml \
  --vault-password-file ansible/.vault_pass \
  --ask-become-pass

# 预计耗时：20-40 分钟
```

**完成后**：
- OMV Web 界面：`http://<树莓派IP>`
- 默认登录：`admin` / `openmediavault`
- **立即修改默认密码！**

### Stage 1: 配置监控

```bash
ansible-playbook -i ansible/inventory/nas.yml \
  ansible/playbooks/nas/1-omv-monitoring.yml \
  --vault-password-file ansible/.vault_pass

# 预计耗时：2-5 分钟
```

**完成后**：
- 自动监控 NVMe 温度（每 10 分钟）
- 自动健康检查（每小时）
- 查看状态：`ssh <user>@<ip> sudo /usr/local/bin/nas-status.sh`

### Stage 2: 配置 Cloudflare Tunnel

**前置步骤**：
1. 登录 [Cloudflare Zero Trust](https://one.dash.cloudflare.com/)
2. 进入 Networks → Tunnels → Create Tunnel
3. 选择 Cloudflared 方式
4. 输入 Tunnel 名称（如 `nas-tunnel`）
5. 复制生成的 Token
6. 将 Token 保存到 `ansible/group_vars/nas_servers/vault.yml`

```bash
# 部署 Cloudflare Tunnel
ansible-playbook -i ansible/inventory/nas.yml \
  ansible/playbooks/nas/2-cloudflare-tunnel.yml \
  --vault-password-file ansible/.vault_pass

# 预计耗时：2-3 分钟
```

**配置 Public Hostname**：
1. 在 Cloudflare Zero Trust Dashboard 中
2. 进入你的 Tunnel → Configure → Public Hostnames
3. 添加：
   - Subdomain: `nas`
   - Domain: `yourdomain.com`
   - Service: `http://localhost:80`
4. 保存后即可通过 `https://nas.yourdomain.com` 访问

## 在 `me` 上部署 Syncthing

如果你需要一个始终在线的同步节点来替代坚果云的“同步中枢”角色，推荐直接在 `me` 上部署 Syncthing，而不是放进 k3s。

```bash
ansible-playbook -i ansible/inventory/testing-k3s.yml \
  ansible/playbooks/nas/3-syncthing.yml \
  --vault-password-file ansible/.vault_pass \
  --limit me
```

默认约定：

- 配置目录：`/var/lib/syncthing`
- 同步数据目录：`/srv/syncthing/data`
- Web UI 域名：`syncthing.panghuli.tech`

说明：

- 实际文件同步继续走 Syncthing 自己的 peer-to-peer 协议
- `syncthing.panghuli.tech` 只用于访问 Web UI
- k3s 侧仅承担反向代理到 `me:8384` 的入口职责

## 验证部署

### 检查 OMV 服务

```bash
# SSH 登录到树莓派
ssh <user>@<ip>

# 查看 OMV 服务状态
sudo systemctl status openmediavault-engined

# 查看 Web 服务
sudo systemctl status nginx
```

### 检查 NVMe 健康

```bash
# 查看 NVMe 信息
sudo nvme list

# 查看 SMART 状态
sudo smartctl -a /dev/nvme0n1

# 查看温度
sudo nvme smart-log /dev/nvme0n1 | grep temperature
```

### 查看监控状态

```bash
# 运行状态仪表板
sudo /usr/local/bin/nas-status.sh

# 查看监控日志
tail -f /var/log/nvme-temp.log
tail -f /var/log/nas-health.log

# 查看定时器状态
systemctl list-timers | grep nas
```

### 检查 Cloudflare Tunnel

```bash
# 查看 cloudflared 服务
sudo systemctl status cloudflared

# 查看连接日志
sudo journalctl -u cloudflared -f

# 查看 tunnel 信息
cloudflared tunnel info
```

## 常见问题

### 1. OMV 安装失败

**症状**：安装脚本报错或超时

**解决**：
```bash
# SSH 登录到树莓派
ssh <user>@<ip>

# 查看安装日志
sudo tail -f /var/log/omv-install.log

# 手动重试安装
wget https://github.com/OpenMediaVault-Plugin-Developers/installScript/raw/master/install
chmod +x install
sudo ./install
```

### 2. NVMe 无法识别

**症状**：`nvme list` 无输出

**解决**：
```bash
# 检查 PCIe 设备
lspci | grep -i nvme

# 如果没有输出，检查：
# 1. 扩展板是否正确连接
# 2. FPC 软排线是否插紧
# 3. 启用 PCIe
sudo raspi-config
# Performance Options → PCIe Speed → Enabled

# 重启
sudo reboot
```

### 3. Cloudflare Tunnel 无法连接

**症状**：`cloudflared` 服务启动失败

**解决**：
```bash
# 检查 token 是否正确
sudo cat /etc/cloudflared/config.yml

# 手动测试连接
sudo cloudflared tunnel run --token <your-token>

# 查看详细日志
sudo journalctl -u cloudflared -n 100 --no-pager
```

### 4. 温度过高

**症状**：NVMe 温度 > 70°C，CPU 温度 > 80°C

**解决**：
- 检查主动散热器是否正常工作
- 为 NVMe 加装散热片
- 改善机箱通风
- 降低环境温度

### 5. Web 界面无法访问

**症状**：浏览器无法打开 `http://<ip>`

**解决**：
```bash
# 检查 nginx 服务
sudo systemctl status nginx

# 检查端口监听
sudo ss -tlnp | grep :80

# 检查防火墙
sudo ufw status

# 如果启用了防火墙，允许 HTTP
sudo ufw allow 80/tcp
sudo ufw reload
```

## 性能优化

### 启用 PCIe Gen 3（实验性）

```bash
# 编辑 config.txt
sudo nano /boot/firmware/config.txt

# 添加以下行
dtparam=pciex1_gen=3

# 保存并重启
sudo reboot

# 测试速度
sudo hdparm -t /dev/nvme0n1
```

**注意**：Gen 3 可能导致不稳定，如果出现问题请改回 Gen 2。

### 性能基准测试

```bash
# 安装测试工具
sudo apt install fio -y

# 顺序读测试
sudo fio --name=seqread --rw=read --bs=1M --size=1G \
  --numjobs=1 --filename=/tmp/testfile

# 顺序写测试
sudo fio --name=seqwrite --rw=write --bs=1M --size=1G \
  --numjobs=1 --filename=/tmp/testfile

# 随机 4K 读测试
sudo fio --name=randread --rw=randread --bs=4k --size=1G \
  --numjobs=4 --filename=/tmp/testfile
```

**预期结果**：
- NVMe 顺序读写：400-500 MB/s
- NVMe 随机 4K：80-100K IOPS
- 千兆网络：900-940 Mbps (~115 MB/s)

## 备份和恢复

### 备份 OMV 配置

```bash
# SSH 登录到树莓派
ssh <user>@<ip>

# 备份配置
sudo omv-backup /tmp/omv-config-$(date +%Y%m%d).tar.gz

# 下载到本地
scp <user>@<ip>:/tmp/omv-config-*.tar.gz ~/backups/
```

### 恢复 OMV 配置

```bash
# 上传备份文件
scp ~/backups/omv-config-*.tar.gz <user>@<ip>:/tmp/

# SSH 登录并恢复
ssh <user>@<ip>
sudo omv-restore /tmp/omv-config-*.tar.gz
```

## 下一步

1. **配置共享文件夹**：
   - 登录 OMV Web 界面
   - Storage → File Systems → 挂载数据分区
   - Storage → Shared Folders → 创建共享文件夹
   - Services → SMB/CIFS → 启用并配置

2. **部署 Nextcloud**（可选）：
   - 参考 `nas/omv/01-替代网盘/` 目录
   - 使用 Docker Compose 部署

3. **配置备份**：
   - 设置定期备份到外部存储
   - 配置云存储同步（rclone）

4. **启用 HTTPS**：
   - 通过 Cloudflare Tunnel 自动提供
   - 或在 OMV 中配置 Let's Encrypt 证书

## 参考文档

- [OpenMediaVault 官方文档](https://docs.openmediavault.org/)
- [树莓派 5 文档](https://www.raspberrypi.com/documentation/computers/raspberry-pi-5.html)
- [Cloudflare Tunnel 文档](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- [NAS 方案详细文档](../nas/plan.md)
