# 树莓派 5 + NVMe SSD 构建 NAS 方案

> 基于树莓派 5 + PCIe NVMe SSD 构建高性能家庭 NAS 存储系统

---

## 硬件配置

本方案基于以下硬件：

| 组件 | 型号/规格 | 说明 |
|------|----------|------|
| 主板 | Raspberry Pi 5 (8GB) | ARM Cortex-A76 四核 2.4GHz |
| 存储 | 三星 970 EVO 1TB | M.2 2280 NVMe SSD (PCIe 3.0 x4) |
| 扩展板 | M.2 PCIe HAT | 支持 2280 尺寸（如 Pimoroni NVMe Base） |
| 电源 | 官方 27W USB-C 适配器 | 5V/5A，必须使用官方电源 |
| 散热 | 主动散热器 | Pi 5 发热较大，必须配备 |

**性能预期**：
- 顺序读写：~500 MB/s（受 Pi 5 PCIe 2.0 x1 限制）
- 随机 IOPS：优于 USB 3.0 方案 3-4 倍
- 网络传输：千兆网络瓶颈 ~125 MB/s，存储性能充足

---

## 快速开始：使用 OpenMediaVault (OMV)

**为什么选择 OMV**：

- ✅ 专为 NAS 设计，功能完整
- ✅ Web 图形界面，易于管理
- ✅ 支持 Samba、NFS、FTP 等多种协议
- ✅ 支持树莓派（通过安装脚本）
- ✅ 插件系统，可扩展功能
- ✅ 活跃的社区支持

### OMV 安装方式

**推荐使用 Ansible 自动化安装**（见下方），或手动安装（见手动安装步骤）。

**重要说明**：

- OMV 不提供官方的树莓派专用镜像，需要先安装 Raspberry Pi OS Lite，然后通过安装脚本安装 OMV
- **OMV 8.0.1** 基于 Debian 13 "Trixie"，仅支持 **64 位系统架构**（AMD64 和 ARM64）
- 树莓派 5 完全支持 ARM64，可以正常安装 OMV 8.0.1
- 必须使用 Lite 版本（无桌面环境），Desktop 版本不支持
- **系统要求**：OMV 8.x 需要 Debian 13 "Trixie"。Raspberry Pi OS 现在已有基于 Debian 13 "Trixie" 的版本（2025-12-04 发布），可以在 "Raspberry Pi OS (other)" 下选择 Lite 版本
- **NVMe 启动**：树莓派 5 原生支持从 NVMe 启动，无需 SD 卡

---

## 快速开始：使用 Ansible 自动化部署（推荐）

### 前置准备

1. **在控制机（你的电脑）上安装 Ansible**：
   ```bash
   pip3 install ansible
   ```

2. **准备树莓派 5**：
   - 使用 Raspberry Pi Imager 将 Raspberry Pi OS Lite (64-bit) 烧录到 NVMe SSD
   - 配置 SSH、用户名、WiFi（在 Imager 的高级设置中）
   - 启动树莓派并记录 IP 地址

3. **配置 Inventory**：
   ```bash
   # 编辑 ansible/inventory/nas.yml
   vim ansible/inventory/nas.yml
   
   # 更新以下内容：
   # - ansible_host: 你的树莓派 IP
   # - ansible_user: 你的用户名
   # - nvme_device: /dev/nvme0n1
   ```

4. **配置 Cloudflare Tunnel Token**（可选，用于远程访问）：
   ```bash
   # 复制示例文件
   cp ansible/group_vars/nas_servers/vault.yml.example \
      ansible/group_vars/nas_servers/vault.yml
   
   # 编辑并填入你的 Cloudflare Tunnel token
   vim ansible/group_vars/nas_servers/vault.yml
   
   # 加密 vault 文件
   echo "your-vault-password" > ansible/.vault_pass
   chmod 600 ansible/.vault_pass
   ansible-vault encrypt ansible/group_vars/nas_servers/vault.yml \
     --vault-password-file ansible/.vault_pass
   ```

### 一键部署

```bash
# 在项目根目录运行
./ansible/scripts/nas-quick-start.sh
```

或者分步骤执行：

```bash
# Stage 0: 安装 OMV（20-40 分钟）
ansible-playbook -i ansible/inventory/nas.yml \
  ansible/playbooks/nas/0-omv-install.yml \
  --vault-password-file ansible/.vault_pass \
  --ask-become-pass

# Stage 1: 配置监控（2-5 分钟）
ansible-playbook -i ansible/inventory/nas.yml \
  ansible/playbooks/nas/1-omv-monitoring.yml \
  --vault-password-file ansible/.vault_pass

# Stage 2: 安装 Cloudflare Tunnel（2-3 分钟，可选）
ansible-playbook -i ansible/inventory/nas.yml \
  ansible/playbooks/nas/2-cloudflare-tunnel.yml \
  --vault-password-file ansible/.vault_pass
```

### 验证部署

```bash
# 查看 NAS 状态
ansible -i ansible/inventory/nas.yml nas_servers -m shell \
  -a "sudo /usr/local/bin/nas-status.sh"
```

**详细文档**：参见 [`ansible/README-NAS.md`](../ansible/README-NAS.md)

---

## 手动安装步骤

如果不使用 Ansible，可以按照以下步骤手动安装：

#### 步骤 1：安装基础操作系统

**方式 A：直接烧录到 NVMe SSD（推荐）**

1. 将三星 970 EVO 安装到 PCIe 扩展板
2. 将扩展板连接到树莓派 5（通过 FPC 软排线）
3. 使用 USB 转 M.2 读卡器将 SSD 连接到电脑
4. 使用 Raspberry Pi Imager 烧录：
   - OS：Raspberry Pi OS (other) → Raspberry Pi OS Lite (64-bit)
   - 目标设备：三星 970 EVO
   - 高级设置（齿轮图标）：
     - 主机名：`nas`（或你喜欢的名称）
     - 用户名和密码
     - WiFi SSID 和密码（如果使用 WiFi）
     - 启用 SSH（使用密码或公钥认证）
     - 时区：Asia/Shanghai
5. 烧录完成后，将 SSD 装回扩展板，连接到树莓派 5
6. 上电启动（树莓派 5 会自动从 NVMe 启动）

**方式 B：使用 SD 卡中转（如果方式 A 不成功）**

1. 先将系统烧录到 SD 卡
2. 从 SD 卡启动树莓派 5
3. 使用 `rpi-imager` 或 `dd` 将系统克隆到 NVMe
4. 更新启动配置，从 NVMe 启动

**验证 NVMe 识别**：

启动后 SSH 登录，检查 NVMe 是否正确识别：

```bash
# 查看块设备
lsblk

# 应该看到类似输出：
# NAME        MAJ:MIN RM   SIZE RO TYPE MOUNTPOINTS
# nvme0n1     259:0    0 931.5G  0 disk 
# ├─nvme0n1p1 259:1    0   512M  0 part /boot/firmware
# └─nvme0n1p2 259:2    0   931G  0 part /

# 查看 NVMe 详细信息
sudo nvme list

# 查看磁盘性能
sudo hdparm -t /dev/nvme0n1
```

#### 步骤 2：系统优化（针对 NVMe SSD）

SSH 登录后，进行以下优化：

```bash
# 更新系统
sudo apt update && sudo apt upgrade -y

# 安装必要工具
sudo apt install -y nvme-cli smartmontools

# 启用 NVMe 电源管理（降低功耗和发热）
echo 'options nvme_core default_ps_max_latency_us=5500' | sudo tee /etc/modprobe.d/nvme.conf

# 优化文件系统挂载参数（提升性能）
sudo cp /etc/fstab /etc/fstab.backup
sudo sed -i 's/defaults/defaults,noatime,commit=60/' /etc/fstab

# 检查 NVMe 健康状态
sudo smartctl -a /dev/nvme0n1

# 查看 NVMe 温度
sudo nvme smart-log /dev/nvme0n1 | grep temperature
```

**重要**：三星 970 EVO 在高负载下可能发热较大，建议：
- 确保扩展板有散热片
- 保持机箱通风良好
- 定期监控温度（建议 < 70°C）

#### 步骤 3：安装 OMV

```bash
# 下载安装脚本
wget https://github.com/OpenMediaVault-Plugin-Developers/installScript/raw/master/install -O install
chmod +x install

# 执行安装（OMV 8.0.1）
sudo ./install
```

**说明**：
- 安装脚本会自动检测系统并安装对应的 OMV 版本
- 如果系统是 Debian 13 "Trixie"，将安装 OMV 8.x（包括 8.0.1）
- 安装过程中可能需要交互确认（如提示 Beta 版本等），按提示操作
- 安装过程可能需要 10-30 分钟，请耐心等待
- 安装完成后系统会自动重启

#### 步骤 4：OMV 初始配置

安装完成后，通过浏览器访问：`http://<树莓派 IP>`

1. **首次登录**：
   - 默认用户名：`admin`
   - 默认密码：`openmediavault`

2. **立即修改密码**：
   - 进入 System → General Settings → Web Administrator Password
   - 设置强密码

3. **配置存储**：
   - 进入 Storage → Disks
   - 确认 NVMe SSD 已识别（显示为 `/dev/nvme0n1`）
   - 查看 SMART 信息，确认健康状态

4. **创建文件系统**（如果需要额外数据分区）：
   
   如果你想将 NVMe 分为系统区和数据区：
   
   ```bash
   # SSH 登录，使用 parted 调整分区
   sudo parted /dev/nvme0n1
   
   # 查看当前分区
   print
   
   # 缩小 root 分区到 100GB（根据需要调整）
   resizepart 2 100GB
   
   # 创建新数据分区
   mkpart primary ext4 100GB 100%
   quit
   
   # 格式化新分区
   sudo mkfs.ext4 /dev/nvme0n1p3
   ```
   
   然后在 OMV Web 界面：
   - Storage → File Systems → Mount
   - 选择新创建的分区并挂载

5. **启用 SMART 监控**：
   - Storage → S.M.A.R.T. → Settings
   - 启用监控
   - 配置定期检查（建议每天）

---

## 配合 Cloudflare 使用

通过 Cloudflare Tunnel 可以安全地将 OMV Web 界面暴露到公网，无需开放端口或配置 DDNS。

### 为什么使用 Cloudflare Tunnel

- ✅ **无需公网 IP**：通过 Cloudflare 隧道访问，无需端口转发
- ✅ **自动 HTTPS**：Cloudflare 自动提供 SSL/TLS 证书
- ✅ **安全防护**：DDoS 防护、WAF 等安全功能
- ✅ **零配置**：无需配置防火墙或路由器

### 安装 Cloudflare Tunnel

#### 步骤 1：在 Cloudflare 创建 Tunnel

1. 登录 [Cloudflare Dashboard](https://dash.cloudflare.com/)
2. 进入 **Zero Trust** → **Networks** → **Tunnels**
3. 点击 **Create a tunnel**
4. 选择 **Cloudflared** 方式
5. 输入 Tunnel 名称（如 `nas-tunnel`）
6. 记录生成的 **Tunnel ID** 和 **Token**（后续需要用到）

#### 步骤 2：在树莓派上安装 cloudflared

#### 步骤 3：在 Cloudflare 配置应用程序路由

1. 在 Cloudflare Dashboard 中，进入 **Zero Trust** → **Networks** → **Tunnels**
2. 点击你创建的 Tunnel（如 `nas-tunnel`）
3. 进入 **Configure** 标签页
4. 点击 **Add a public hostname**
5. 配置路由规则：
   - **Subdomain**: `nas`（或你想要的子域名）
   - **Domain**: 选择你的域名（如 `yourdomain.com`）
   - **Service**: 选择 **HTTP**
   - **URL**: `http://localhost:80`（OMV 默认端口）
6. 点击 **Save hostname** 保存配置

**说明**：

- Cloudflare 会自动创建对应的 DNS 记录（CNAME）
- 无需手动在 DNS 中配置
- 路由配置会立即生效

#### 步骤 5：访问 OMV

配置完成后，可以通过以下方式访问：

- **本地访问**：`http://<树莓派 IP>`
- **公网访问**：`https://nas.yourdomain.com`（通过 Cloudflare，自动 HTTPS）

### 安全建议

1. **启用 Cloudflare Zero Trust 访问控制**（推荐）：
   - 在 Cloudflare Zero Trust 中配置访问策略
   - 可以要求邮箱验证、地理位置限制等
   - 在 Tunnel 配置中添加 **Access** 策略

2. **修改 OMV 默认密码**：
   - 登录 OMV Web 界面后立即修改默认密码
   - 使用强密码

3. **定期更新 cloudflared**：

   ```bash
   # 更新 cloudflared
   sudo cloudflared update
   sudo systemctl restart cloudflared
   ```

---

## 解决单点故障问题

单点故障可能导致数据丢失或服务中断。以下是针对家庭 NAS 的解决方案：

### 1. 数据备份策略

#### 1.1 定期数据备份

**使用 OMV 内置备份功能**：

1. 在 OMV Web 界面中，进入 **Services** → **Rsync** → **Server**
2. 启用 Rsync 服务器
3. 创建备份任务：**Services** → **Scheduled Tasks** → **Rsync**
4. 配置备份目标（可以是另一台 NAS、云存储或外部硬盘）

**使用 rsync 脚本自动备份**：

```bash
# 创建备份脚本
sudo nano /usr/local/bin/backup-nas.sh
```

脚本内容：

```bash
#!/bin/bash
BACKUP_DIR="/path/to/backup/destination"
SOURCE_DIR="/srv/dev-disk-by-*"
DATE=$(date +%Y%m%d_%H%M%S)
LOG_FILE="/var/log/nas-backup.log"

# 创建备份目录
mkdir -p "$BACKUP_DIR/$DATE"

# 执行备份
rsync -av --delete "$SOURCE_DIR" "$BACKUP_DIR/$DATE" >> "$LOG_FILE" 2>&1

# 删除 30 天前的备份
find "$BACKUP_DIR" -type d -mtime +30 -exec rm -rf {} \;

echo "$(date): Backup completed" >> "$LOG_FILE"
```

设置定时任务：

```bash
# 编辑 crontab
sudo crontab -e

# 添加每天凌晨 2 点执行备份
0 2 * * * /usr/local/bin/backup-nas.sh
```

#### 1.2 云存储备份

**使用 rclone 同步到云存储**（Google Drive、OneDrive、阿里云盘等）：

```bash
# 安装 rclone
curl https://rclone.org/install.sh | sudo bash

# 配置云存储
rclone config

# 创建同步脚本
sudo nano /usr/local/bin/sync-to-cloud.sh
```

脚本内容：

```bash
#!/bin/bash
SOURCE_DIR="/srv/dev-disk-by-*"
REMOTE_NAME="your_remote_name"
REMOTE_PATH="nas-backup"

rclone sync "$SOURCE_DIR" "$REMOTE_NAME:$REMOTE_PATH" \
  --progress \
  --log-file=/var/log/rclone-sync.log \
  --log-level=INFO
```

#### 1.3 3-2-1 备份策略

- **3** 份数据副本（原始数据 + 2 份备份）
- **2** 种不同的存储介质（本地 + 云存储）
- **1** 份异地备份（防止火灾、水灾等）

### 2. 系统备份和快速恢复

#### 2.1 系统镜像备份

定期备份整个系统盘，以便快速恢复：

```bash
# 创建系统备份脚本
sudo nano /usr/local/bin/backup-system.sh
```

脚本内容：

```bash
#!/bin/bash
BACKUP_DIR="/mnt/backup/system"
DATE=$(date +%Y%m%d)
DISK_DEVICE="/dev/sda"

# 创建备份目录
mkdir -p "$BACKUP_DIR"

# 使用 dd 备份（需要系统盘未挂载或使用 live CD）
# 注意：此操作需要系统处于维护模式或使用外部工具
sudo dd if="$DISK_DEVICE" of="$BACKUP_DIR/system-backup-$DATE.img bs=4M status=progress

# 压缩备份
gzip "$BACKUP_DIR/system-backup-$DATE.img"
```

**使用 Raspberry Pi Imager 备份**：

1. 将系统盘连接到另一台电脑
2. 使用 Raspberry Pi Imager 的 "Use custom image" 功能
3. 选择 "Read" 模式，将系统盘内容保存为镜像文件

#### 2.2 OMV 配置备份

定期备份 OMV 配置，便于快速恢复设置：

```bash
# 创建配置备份脚本
sudo nano /usr/local/bin/backup-omv-config.sh
```

脚本内容：

```bash
#!/bin/bash
BACKUP_DIR="/mnt/backup/omv-config"
DATE=$(date +%Y%m%d)

mkdir -p "$BACKUP_DIR"

# 备份 OMV 配置
sudo omv-backup "$BACKUP_DIR/omv-config-$DATE.tar.gz"
```

设置定时任务：

```bash
sudo crontab -e
# 每周备份一次配置
0 3 * * 0 /usr/local/bin/backup-omv-config.sh
```

### 3. 硬件冗余（可选）

#### 3.1 RAID 配置

如果有多块硬盘，可以在 OMV 中配置 RAID：

1. 进入 OMV Web 界面 → **Storage** → **RAID Management**
2. 创建 RAID 1（镜像）或 RAID 5（带奇偶校验）
3. 配置自动重建

**注意**：树莓派性能有限，RAID 5 可能影响性能，建议使用 RAID 1。

#### 3.2 备用硬件

- 准备备用树莓派 5（相同型号）
- 准备备用官方 27W 电源适配器
- 准备备用 NVMe SSD 或 USB SSD

### 4. 监控和告警

#### 4.1 系统监控

安装监控工具，及时发现故障：

```bash
# 安装监控工具
sudo apt install htop smartmontools nvme-cli -y

# 检查 NVMe 健康状态
sudo smartctl -a /dev/nvme0n1

# 查看 NVMe 详细信息
sudo nvme smart-log /dev/nvme0n1

# 监控 NVMe 温度
watch -n 5 'sudo nvme smart-log /dev/nvme0n1 | grep temperature'
```

**NVMe 特定监控**：

创建 NVMe 温度监控脚本：

```bash
sudo tee /usr/local/bin/nvme-temp-monitor.sh > /dev/null << 'SCRIPT'
#!/bin/bash
LOG_FILE="/var/log/nvme-temp.log"
ALERT_EMAIL="your-email@example.com"
TEMP_THRESHOLD=70

TEMP=$(sudo nvme smart-log /dev/nvme0n1 | grep temperature | awk '{print $3}')

if [ "$TEMP" -gt "$TEMP_THRESHOLD" ]; then
    echo "$(date): NVMe temperature is ${TEMP}°C" >> "$LOG_FILE"
    echo "NVMe temperature warning: ${TEMP}°C" | mail -s "NAS Alert" "$ALERT_EMAIL"
fi
SCRIPT

sudo chmod +x /usr/local/bin/nvme-temp-monitor.sh

# 添加定时任务（每 10 分钟检查一次）
echo '*/10 * * * * root /usr/local/bin/nvme-temp-monitor.sh' | sudo tee /etc/cron.d/nvme-temp-monitor
```

#### 4.2 邮件告警

配置 OMV 邮件通知：

1. 进入 OMV Web 界面 → **System** → **Notification**
2. 配置 SMTP 设置
3. 启用各种告警通知（磁盘故障、服务异常等）

#### 4.3 健康检查脚本

创建健康检查脚本，定期检查系统状态：

```bash
sudo tee /usr/local/bin/health-check.sh > /dev/null << 'SCRIPT'
#!/bin/bash
LOG_FILE="/var/log/nas-health.log"
ALERT_EMAIL="your-email@example.com"

# 检查磁盘空间
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
if [ "$DISK_USAGE" -gt 80 ]; then
    echo "$(date): Disk usage is ${DISK_USAGE}%" >> "$LOG_FILE"
    echo "Disk usage warning: ${DISK_USAGE}%" | mail -s "NAS Alert" "$ALERT_EMAIL"
fi

# 检查服务状态
if ! systemctl is-active --quiet openmediavault; then
    echo "$(date): OMV service is down" >> "$LOG_FILE"
    echo "OMV service is down" | mail -s "NAS Alert" "$ALERT_EMAIL"
fi

# 检查 NVMe 健康状态
NVME_HEALTH=$(sudo nvme smart-log /dev/nvme0n1 | grep "critical_warning" | awk '{print $3}')
if [ "$NVME_HEALTH" != "0x00" ]; then
    echo "$(date): NVMe critical warning detected" >> "$LOG_FILE"
    echo "NVMe health warning: $NVME_HEALTH" | mail -s "NAS Alert" "$ALERT_EMAIL"
fi

# 检查 NVMe SMART 状态
SMART_STATUS=$(sudo smartctl -H /dev/nvme0n1 | grep "SMART overall-health" | awk '{print $6}')
if [ "$SMART_STATUS" != "PASSED" ]; then
    echo "$(date): NVMe SMART check failed" >> "$LOG_FILE"
    echo "NVMe SMART check failed" | mail -s "NAS Alert" "$ALERT_EMAIL"
fi

# 检查 NVMe 寿命（Percentage Used）
PERCENTAGE_USED=$(sudo nvme smart-log /dev/nvme0n1 | grep "percentage_used" | awk '{print $3}' | sed 's/%//')
if [ "$PERCENTAGE_USED" -gt 80 ]; then
    echo "$(date): NVMe wear level is ${PERCENTAGE_USED}%" >> "$LOG_FILE"
    echo "NVMe wear warning: ${PERCENTAGE_USED}% used" | mail -s "NAS Alert" "$ALERT_EMAIL"
fi
SCRIPT

sudo chmod +x /usr/local/bin/health-check.sh

# 添加定时任务（每小时检查一次）
echo '0 * * * * root /usr/local/bin/health-check.sh' | sudo tee /etc/cron.d/nas-health-check
```

### 5. 快速恢复流程

#### 5.1 数据恢复

1. 从备份恢复数据：使用 rsync 或 rclone 从备份位置恢复
2. 恢复共享配置：从 OMV 配置备份恢复

#### 5.2 系统恢复

1. 使用 Raspberry Pi Imager 将系统镜像烧录到新盘
2. 恢复 OMV 配置：`sudo omv-restore /path/to/backup.tar.gz`
3. 验证服务正常运行

### 6. 最佳实践总结

- ✅ **定期备份**：至少每周备份一次重要数据
- ✅ **多重备份**：本地备份 + 云存储备份
- ✅ **测试恢复**：定期测试备份恢复流程
- ✅ **监控告警**：配置监控和邮件告警
- ✅ **文档记录**：记录配置和恢复步骤
- ✅ **定期更新**：保持系统和软件更新

---

## 树莓派 5 + NVMe 特定优化

### 1. 性能优化

#### 1.1 启用 PCIe Gen 3（实验性）

树莓派 5 默认使用 PCIe Gen 2，可以尝试启用 Gen 3（可能不稳定）：

```bash
# 编辑 config.txt
sudo nano /boot/firmware/config.txt

# 添加以下行
dtparam=pciex1_gen=3

# 重启
sudo reboot

# 验证速度
sudo hdparm -t /dev/nvme0n1
```

**注意**：Gen 3 可能导致不稳定，如果出现问题请改回 Gen 2。

#### 1.2 I/O 调度器优化

NVMe SSD 使用 `none` 调度器性能最佳：

```bash
# 查看当前调度器
cat /sys/block/nvme0n1/queue/scheduler

# 设置为 none
echo none | sudo tee /sys/block/nvme0n1/queue/scheduler

# 永久生效
echo 'ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/scheduler}="none"' | sudo tee /etc/udev/rules.d/60-nvme-scheduler.rules
```

#### 1.3 文件系统优化

```bash
# 启用 TRIM（延长 SSD 寿命）
sudo systemctl enable fstrim.timer
sudo systemctl start fstrim.timer

# 手动执行 TRIM
sudo fstrim -av
```

### 2. 散热管理

树莓派 5 + NVMe SSD 发热较大，需要良好散热：

#### 2.1 监控温度

```bash
# 查看 CPU 温度
vcgencmd measure_temp

# 查看 NVMe 温度
sudo nvme smart-log /dev/nvme0n1 | grep temperature

# 实时监控
watch -n 2 'echo "CPU: $(vcgencmd measure_temp)" && echo "NVMe: $(sudo nvme smart-log /dev/nvme0n1 | grep temperature)"'
```

#### 2.2 温度阈值

| 组件 | 正常 | 警告 | 危险 |
|------|------|------|------|
| CPU | < 60°C | 60-80°C | > 80°C |
| NVMe | < 50°C | 50-70°C | > 70°C |

**建议**：
- 使用官方主动散热器（带风扇）
- 为 NVMe SSD 加装散热片
- 保持机箱通风良好
- 避免在密闭空间运行

### 3. 电源管理

树莓派 5 功耗较高，必须使用官方 27W 电源：

```bash
# 检查是否欠压（undervoltage）
vcgencmd get_throttled

# 输出 0x0 表示正常
# 如果出现 0x50000 或其他值，说明供电不足
```

**常见供电问题**：
- 使用非官方电源 → 更换为官方 27W 电源
- USB-C 线缆质量差 → 使用官方线缆或高质量 USB-C 线
- NVMe SSD 功耗过高 → 检查 SSD 规格，考虑更换低功耗型号

### 4. 故障排查

#### 4.1 NVMe 无法识别

```bash
# 检查 PCIe 设备
lspci

# 应该看到类似输出：
# 0000:01:00.0 Non-Volatile memory controller: Samsung Electronics Co Ltd ...

# 如果没有输出，检查：
# 1. 扩展板是否正确连接
# 2. FPC 软排线是否插紧
# 3. 是否启用了 PCIe（默认启用）

# 启用 PCIe（如果被禁用）
sudo raspi-config
# Performance Options → PCIe Speed → Enabled
```

#### 4.2 启动失败

如果从 NVMe 启动失败：

```bash
# 方法 1：更新 EEPROM（确保支持 NVMe 启动）
sudo rpi-eeprom-update -a
sudo reboot

# 方法 2：手动设置启动顺序
sudo raspi-config
# Advanced Options → Boot Order → NVMe/USB Boot
```

#### 4.3 性能不达预期

```bash
# 测试读写速度
sudo hdparm -t /dev/nvme0n1

# 如果速度低于 400 MB/s：
# 1. 检查是否使用 PCIe Gen 2（应该是）
# 2. 检查 I/O 调度器（应该是 none）
# 3. 检查温度（过热会降频）
# 4. 检查供电（欠压会限制性能）
```

#### 4.4 OMV Web 界面无法访问

```bash
# 检查 OMV 服务状态
sudo systemctl status openmediavault-engined

# 重启 OMV 服务
sudo systemctl restart openmediavault-engined

# 检查防火墙
sudo ufw status

# 如果启用了防火墙，允许 HTTP
sudo ufw allow 80/tcp
```

### 5. 性能基准测试

完成安装后，建议进行性能测试：

```bash
# 安装测试工具
sudo apt install fio -y

# 顺序读测试
sudo fio --name=seqread --rw=read --bs=1M --size=1G --numjobs=1 --filename=/dev/nvme0n1p2

# 顺序写测试
sudo fio --name=seqwrite --rw=write --bs=1M --size=1G --numjobs=1 --filename=/tmp/testfile

# 随机读测试
sudo fio --name=randread --rw=randread --bs=4k --size=1G --numjobs=4 --filename=/tmp/testfile

# 网络传输测试（从另一台机器）
# 安装 iperf3
sudo apt install iperf3 -y

# 在树莓派上启动服务端
iperf3 -s

# 在客户端测试
iperf3 -c <树莓派 IP>
```

**预期结果**：
- NVMe 顺序读写：400-500 MB/s
- NVMe 随机 4K：80-100K IOPS
- 千兆网络：900-940 Mbps (~115 MB/s)

---

## 参考资源

### 系统文档

- OpenMediaVault 官方文档：<https://docs.openmediavault.org/>
- 树莓派 5 文档：<https://www.raspberrypi.com/documentation/computers/raspberry-pi-5.html>
- NVMe 启动指南：<https://www.raspberrypi.com/documentation/computers/raspberry-pi.html#nvme-ssd-boot>

### 硬件相关

- 树莓派官方文档：<https://www.raspberrypi.com/documentation/>
- 三星 970 EVO 规格：<https://www.samsung.com/semiconductor/minisite/ssd/product/consumer/970evo/>

### 社区资源

- OMV 论坛：<https://forum.openmediavault.org/>
- 树莓派论坛：<https://forums.raspberrypi.com/>

---

## 总结

**你的配置优势**：

✅ **高性能**：树莓派 5 CPU 性能是 4B 的 2-3 倍  
✅ **快速存储**：NVMe SSD 提供 ~500 MB/s 速度和优秀的 IOPS  
✅ **可靠性高**：三星 970 EVO 是成熟稳定的企业级 SSD  
✅ **内置整洁**：PCIe 扩展板无外置线缆  
✅ **原生启动**：无需 SD 卡，直接从 NVMe 启动  

**注意事项**：

⚠️ **散热**：必须配备主动散热器，监控温度  
⚠️ **供电**：必须使用官方 27W 电源  
⚠️ **备份**：定期备份数据和系统配置  
⚠️ **监控**：配置 SMART 监控和温度告警  

**构建完成后，您将拥有一个高性能、低功耗、静音运行的家庭 NAS 存储系统！**
