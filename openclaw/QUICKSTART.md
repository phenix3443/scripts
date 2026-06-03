# OpenClaw 快速开始

> 5 分钟完成自动化部署

---

## 📋 前置条件

- ✅ kubectl 可访问 k3s 集群
- ✅ Longhorn、Prometheus、Grafana 已安装
- ⏳ Cloudflare R2 账号（或 Backblaze B2 / 阿里云 OSS）
- ⏳ Telegram Bot Token（可选，用于告警）

---

## 🚀 一键部署

### 1. 获取凭证（5 分钟）

#### Cloudflare R2（推荐，10GB 免费）

1. 登录 https://dash.cloudflare.com/ → R2
2. Create bucket: `openclaw-backup`
3. Manage R2 API Tokens → Create API token
4. 复制：Access Key ID、Secret Access Key、Endpoint URL

#### Telegram Bot（可选）

1. Telegram 搜索 `@BotFather` → `/newbot`
2. 按提示创建，复制 token
3. 与 bot 私聊或加入群组
4. 访问 `https://api.telegram.org/bot<TOKEN>/getUpdates`
5. 复制 `chat.id`

### 2. 配置 secrets.env（1 分钟）

字段清单与占位示例见 `openclaw/scripts/secrets.template.env`。

```bash
cd /Users/lsl/github/womenlia/home-lab
vi openclaw/scripts/secrets.env
```

填入：

```bash
# 已有的 API keys（保持不变）
SKYAPI_API_KEY=sk-sky-xxx
ALIYUN_API_KEY=sk-sp-xxx

# 新增：S3 备份
S3_ACCESS_KEY_ID=<从 R2 复制>
S3_SECRET_ACCESS_KEY=<从 R2 复制>
S3_ENDPOINT=https://<account-id>.r2.cloudflarestorage.com
S3_BUCKET=openclaw-backup
S3_REGION=auto

# 新增：Telegram 告警（可选）
TELEGRAM_BOT_TOKEN=<从 BotFather 复制>
TELEGRAM_CHAT_ID=<从 getUpdates 复制>
```

### 3. 验证 Telegram + S3（可选）

```bash
./openclaw/scripts/openclaw.sh test-connectivity
# ./openclaw/scripts/openclaw.sh test-connectivity --send-telegram
```

安装工具：仓库根目录执行 `make install`（含 **awscli**，用于 S3 检测）。仅测 Telegram 只需 `curl`；若访问 `api.telegram.org` 出现证书错误，可先 `./openclaw/scripts/openclaw.sh test-connectivity --skip-telegram` 只测 S3。

### 4. 一键配置（3 分钟）

```bash
# 配置 S3 备份
./openclaw/scripts/setup-backup-target.sh

# 导入 Grafana Dashboard
./openclaw/scripts/setup-grafana-dashboard.sh

# 配置 Telegram 告警（可选）
./openclaw/scripts/setup-alertmanager.sh

# 验证
./openclaw/scripts/openclaw.sh check
```

### 5. 验证（1 分钟）

```bash
# 检查 Longhorn 备份配置
kubectl -n longhorn-system get setting backup-target -o jsonpath='{.value}'
# 输出: s3://openclaw-backup@auto/

# 检查 Grafana Dashboard
# 访问 Grafana UI → Dashboards → 搜索 "OpenClaw"

# 测试 Telegram 告警（可选）
kubectl -n openclaw delete pod hanbao-0
# 5 分钟后 Telegram 收到告警
```

---

## 📚 详细文档

- **[完整自动化指南](docs/automation-setup.md)** — 所有步骤的详细说明
- **[灾难恢复](docs/disaster-recovery.md)** — 备份恢复流程
- **[部署文档](../infrastructure/01-architecture.md)** — OpenClaw 相关架构与配置

---

## 🆘 故障排查

| 问题 | 解决 |
|------|------|
| S3 连接失败 | 检查 Endpoint URL 格式，确认 bucket 已创建 |
| Grafana 未显示 Dashboard | `kubectl get cm -n monitoring openclaw-dashboard` |
| Telegram 未收到告警 | 检查 bot token 和 chat ID，确认 bot 在群组有权限 |
| CI 失败 | 检查 GitHub Secret `KUBECONFIG_B64` 是否正确 |

详见：`docs/automation-setup.md` 第 6 节

---

## ⚡ 下一步

- **配置 GitHub Actions CI**：见 `docs/automation-setup.md` 第 4 节
- **部署更多 Agent**：`./openclaw/scripts/openclaw.sh create <name>`
- **升级 Operator**：`./openclaw/scripts/openclaw.sh upgrade`
