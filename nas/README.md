# NAS 部署方案

基于树莓派 5 + NVMe SSD 构建 OpenMediaVault NAS 系统。

## 文档导航

### 📋 方案文档

- **[plan.md](plan.md)** - 完整的 NAS 部署方案
  - 硬件配置和选型
  - 手动安装步骤
  - 系统优化和调优
  - 监控和告警配置
  - 故障排查指南
  - 性能基准测试

### 🚀 快速开始

- **[ANSIBLE-SETUP.md](ANSIBLE-SETUP.md)** - Ansible 自动化部署指南（推荐）
  - 5 分钟配置，30 分钟部署
  - 一键安装 OMV + 监控 + Cloudflare Tunnel
  - 详细的验证和故障排查步骤

### 📦 替代网盘方案

- **[omv/01-替代网盘/](omv/01-替代网盘/)** - 使用 Nextcloud 替代百度网盘
  - [01-需求分析.md](omv/01-替代网盘/01-需求分析.md) - 功能需求和使用场景
  - [02-方案架构.md](omv/01-替代网盘/02-方案架构.md) - Nextcloud + Cloudflare Tunnel 架构
  - [03-落地实施.md](omv/01-替代网盘/03-落地实施.md) - Docker Compose 部署步骤

## 硬件配置

本方案基于以下硬件：

| 组件 | 型号/规格 | 价格 |
|------|----------|------|
| 主板 | Raspberry Pi 5 (8GB) | ¥600 |
| 存储 | 三星 970 EVO 1TB (M.2 2280 NVMe) | 已有 |
| 扩展板 | M.2 PCIe HAT（支持 2280） | ¥200-300 |
| 电源 | 官方 27W USB-C 适配器 | ¥80 |
| 散热 | 主动散热器 | ¥50 |
| **总计** | | **¥930-1030** |

**性能预期**：
- NVMe 顺序读写：~500 MB/s
- 千兆网络传输：~125 MB/s
- 存储性能充足，网络为瓶颈

## 快速开始

### 方式 1: Ansible 自动化部署（推荐）

```bash
# 1. 克隆仓库
git clone https://github.com/womenlia/home-lab.git
cd home-lab

# 2. 安装 Ansible
pip3 install ansible

# 3. 配置 inventory
vim ansible/inventory/nas.yml
# 修改 ansible_host 为你的树莓派 IP

# 4. 一键部署
./ansible/scripts/nas-quick-start.sh
```

**详细步骤**: 参见 [ANSIBLE-SETUP.md](ANSIBLE-SETUP.md)

### 方式 2: 手动安装

参见 [plan.md](plan.md) 中的"手动安装步骤"章节。

## 部署内容

### ✅ 基础系统
- Raspberry Pi OS Lite (64-bit) 基于 Debian 13 "Trixie"
- 从 NVMe SSD 启动（无需 SD 卡）
- 时区配置和 NTP 同步
- NVMe 优化（电源管理、I/O 调度器、TRIM）

### ✅ OpenMediaVault 8.x
- Web 管理界面
- 文件共享（SMB/CIFS、NFS）
- 用户和权限管理
- 磁盘管理和 SMART 监控

### ✅ 监控和告警
- NVMe 温度监控（每 10 分钟）
- 系统健康检查（每小时）
- 磁盘空间和 SMART 状态监控
- 状态仪表板脚本

### ✅ 远程访问（可选）
- Cloudflare Tunnel（HTTPS 自动证书）
- 无需公网 IP 和端口转发
- DDoS 防护和 WAF

### ✅ Nextcloud（可选）
- 多端同步（Windows/macOS/Linux/iOS/Android）
- 文件分享（密码、过期时间）
- 版本控制和回收站

## 访问方式

### 本地访问
- OMV Web 界面: `http://<树莓派IP>`
- 默认登录: `admin` / `openmediavault`

### 远程访问（配置 Cloudflare Tunnel 后）
- OMV Web 界面: `https://nas.yourdomain.com`
- Nextcloud: `https://drive.yourdomain.com`

## 验证部署

```bash
# 查看 NAS 状态
ssh <user>@<ip> sudo /usr/local/bin/nas-status.sh

# 或使用 Ansible
ansible -i ansible/inventory/nas.yml nas_servers -m shell \
  -a "sudo /usr/local/bin/nas-status.sh"
```

## 下一步

1. **修改默认密码** - 登录 OMV 后立即修改
2. **配置存储** - 创建共享文件夹
3. **启用文件共享** - 配置 SMB/CIFS 或 NFS
4. **配置远程访问** - 设置 Cloudflare Tunnel 公网域名
5. **部署 Nextcloud** - 参考 `omv/01-替代网盘/` 目录
6. **配置备份** - 设置定期备份和云存储同步

## 维护命令

```bash
# 查看状态
sudo /usr/local/bin/nas-status.sh

# 查看监控日志
tail -f /var/log/nvme-temp.log
tail -f /var/log/nas-health.log

# 查看 OMV 日志
sudo journalctl -u openmediavault-engined -f

# 备份 OMV 配置
sudo omv-backup /tmp/omv-backup-$(date +%Y%m%d).tar.gz

# 更新系统
sudo apt update && sudo apt upgrade -y
```

## 故障排查

常见问题和解决方案：

1. **NVMe 无法识别** - 检查扩展板连接和 PCIe 启用
2. **OMV Web 界面无法访问** - 检查服务状态和防火墙
3. **温度过高** - 检查散热器和通风
4. **性能不达预期** - 检查 I/O 调度器和 PCIe 速度

详细故障排查步骤：
- [plan.md 故障排查](plan.md#故障排查)
- [ANSIBLE-SETUP.md 常见问题](ANSIBLE-SETUP.md#常见问题)

## Ansible Playbooks

自动化部署脚本位于 `../ansible/playbooks/nas/`：

- **0-omv-install.yml** - 安装 OMV（20-40 分钟）
- **1-omv-monitoring.yml** - 配置监控（2-5 分钟）
- **2-cloudflare-tunnel.yml** - 安装 Cloudflare Tunnel（2-3 分钟）

详细说明：[../ansible/README-NAS.md](../ansible/README-NAS.md)

## 参考资源

### 官方文档
- [OpenMediaVault 官方文档](https://docs.openmediavault.org/)
- [树莓派 5 文档](https://www.raspberrypi.com/documentation/computers/raspberry-pi-5.html)
- [Cloudflare Tunnel 文档](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)

### 社区资源
- [OMV 论坛](https://forum.openmediavault.org/)
- [树莓派论坛](https://forums.raspberrypi.com/)

## 贡献

欢迎提交 Issue 和 Pull Request！

## 许可证

MIT License
