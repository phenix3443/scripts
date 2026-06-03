# OpenClaw 自动化部署指南

> 一键配置备份、监控、告警，减少手动操作

---

## 前置条件

- kubectl 可访问集群
- `openclaw/scripts/secrets.env` 已配置（ansible-vault 加密）
- Longhorn、Prometheus/Alertmanager、Grafana 已安装

---

## 1. S3 备份存储配置

### 1.1 选择 S3 兼容服务

| 服务 | 免费额度 | 成本 | 推荐度 |
|------|---------|------|--------|
| **Cloudflare R2** | 10GB | $0.015/GB/月 | ⭐⭐⭐⭐⭐ |
| Backblaze B2 | 10GB | $0.005/GB/月 | ⭐⭐⭐⭐ |
| 阿里云 OSS | 无 | ¥0.12/GB/月 | ⭐⭐⭐ |
| MinIO（自建） | - | 硬件成本 | ⭐⭐ |

**推荐 Cloudflare R2**（你已在用 Cloudflare Tunnel）：

#### 步骤 1：创建 R2 Bucket

1. 登录 [Cloudflare Dashboard](https://dash.cloudflare.com/)
2. 左侧菜单 → **R2 Object Storage**
3. 点击 **Create bucket**
4. 填写：
   - Bucket name: `openclaw-backup`
   - Location: Auto（或选择离你最近的区域）
5. 点击 **Create bucket**

#### 步骤 2：生成 API Token

1. 在 R2 页面，点击右上角 **Manage R2 API Tokens**
2. 点击 **Create API token**
3. 配置：
   - Token name: `longhorn-backup`
   - Permissions: **Admin Read & Write**（或仅选 `openclaw-backup` bucket）
   - TTL: **Forever**（或按需设置过期时间）
4. 点击 **Create API Token**
5. **立即复制并保存**（只显示一次）：
   - **Access Key ID**：`xxxxxxxxxxxxxxxxxxxxx`
   - **Secret Access Key**：`yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy`
   - **Endpoint URL**：`https://<account-id>.r2.cloudflarestorage.com`

#### 步骤 3：记录到 secrets.env

```bash
S3_ACCESS_KEY_ID=xxxxxxxxxxxxxxxxxxxxx
S3_SECRET_ACCESS_KEY=yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy
S3_ENDPOINT=https://<account-id>.r2.cloudflarestorage.com
S3_BUCKET=openclaw-backup
S3_REGION=auto
```

**注意**：Endpoint URL 中的 `<account-id>` 是你的 Cloudflare Account ID（R2 页面顶部可见）。

---

#### 备选方案：Backblaze B2（成本更低）

<details>
<summary>点击展开 Backblaze B2 配置步骤</summary>

**优势**：$0.005/GB/月（R2 的 1/3），10GB 免费

1. 注册 [Backblaze](https://www.backblaze.com/b2/sign-up.html)
2. 登录后 → **Buckets** → **Create a Bucket**
   - Bucket Name: `openclaw-backup`
   - Files in Bucket: **Private**
   - Encryption: **Disable**（Longhorn 自己加密）
3. 左侧 **App Keys** → **Add a New Application Key**
   - Name: `longhorn-backup`
   - Allow access to Bucket: `openclaw-backup`
   - Type of Access: **Read and Write**
4. 点击 **Create New Key**，复制：
   - **keyID**（作为 `S3_ACCESS_KEY_ID`）
   - **applicationKey**（作为 `S3_SECRET_ACCESS_KEY`）
   - **Endpoint**：查看 Bucket 详情页的 **Endpoint**（如 `s3.us-west-004.backblazeb2.com`）

**secrets.env 配置**：

```bash
S3_ACCESS_KEY_ID=<keyID>
S3_SECRET_ACCESS_KEY=<applicationKey>
S3_ENDPOINT=https://s3.us-west-004.backblazeb2.com
S3_BUCKET=openclaw-backup
S3_REGION=us-west-004
```

</details>

---

#### 备选方案：阿里云 OSS

<details>
<summary>点击展开阿里云 OSS 配置步骤</summary>

**优势**：国内访问快，¥0.12/GB/月

1. 登录 [阿里云控制台](https://oss.console.aliyun.com/)
2. **对象存储 OSS** → **Bucket 列表** → **创建 Bucket**
   - Bucket 名称: `openclaw-backup`
   - 地域: 选择离你最近的（如华东1-杭州）
   - 读写权限: **私有**
3. **AccessKey 管理**（右上角头像下拉）→ **创建 AccessKey**
   - 复制 **AccessKey ID** 和 **AccessKey Secret**
4. 记录 Endpoint：Bucket 详情页 → **访问域名** → **外网访问**（如 `oss-cn-hangzhou.aliyuncs.com`）

**secrets.env 配置**：

```bash
S3_ACCESS_KEY_ID=<AccessKey ID>
S3_SECRET_ACCESS_KEY=<AccessKey Secret>
S3_ENDPOINT=https://oss-cn-hangzhou.aliyuncs.com
S3_BUCKET=openclaw-backup
S3_REGION=cn-hangzhou
```

</details>

### 1.2 配置 secrets.env

编辑 `openclaw/scripts/secrets.env`（会自动加密）：

```bash
# S3 Backup Target
S3_ACCESS_KEY_ID=your-r2-access-key
S3_SECRET_ACCESS_KEY=your-r2-secret-key
S3_ENDPOINT=https://xxx.r2.cloudflarestorage.com
S3_BUCKET=openclaw-backup
S3_REGION=auto
```

### 1.3 验证 Telegram 与 S3（推荐）

```bash
cd /Users/lsl/github/womenlia/home-lab
./openclaw/scripts/openclaw.sh test-connectivity
# Optional: send one test message to TELEGRAM_CHAT_ID
./openclaw/scripts/openclaw.sh test-connectivity --send-telegram
```

- Telegram：调用 `getMe` 校验 bot token。
- S3：若已安装 `aws` CLI，对 `S3_BUCKET` 执行 `aws s3 ls`（使用 `S3_ENDPOINT`）。
- **常见错误**：`S3_ENDPOINT` 填成了 Secret Key；必须是 `https://...` 形式的端点地址（R2 控制台可复制）。

### 1.4 一键配置 Longhorn

```bash
cd /Users/lsl/github/womenlia/home-lab

# 编辑 secrets.env，填入上面获取的 S3 凭证
vi openclaw/scripts/secrets.env

# 运行配置脚本
./openclaw/scripts/setup-backup-target.sh
```

**自动完成**：
- 创建 K8s Secret `longhorn-backup-s3`（含 Access Key、Secret Key、Endpoint）
- 配置 Longhorn `backup-target` Setting（`s3://openclaw-backup@auto/`）
- 配置 `backup-target-credential-secret` Setting（指向 Secret）
- 验证连接

**验证**：

1. **命令行验证**：
   ```bash
   kubectl -n longhorn-system get setting backup-target -o jsonpath='{.value}'
   # 输出: s3://openclaw-backup@auto/
   ```

2. **Longhorn UI 验证**：
   - 访问 Longhorn UI（`kubectl port-forward -n longhorn-system svc/longhorn-frontend 8000:80`）
   - Settings → General → **Backup Target**（显示 `s3://openclaw-backup@auto/`）
   - Settings → General → **Backup Target Credential Secret**（显示 `longhorn-backup-s3`）

3. **触发测试备份**（可选）：
   - Longhorn UI → Volume → 选择 `openclaw` 相关 volume
   - 点击 **Create Backup**
   - 查看 Backup 页面是否成功上传到 S3

---

## 2. Grafana Dashboard 自动导入

### 2.1 方式一：ConfigMap 自动发现（推荐）

**适用场景**：kube-prometheus-stack（带 Grafana sidecar）

**步骤**：

```bash
cd /Users/lsl/github/womenlia/home-lab

# 默认使用 monitoring namespace
./openclaw/scripts/setup-grafana-dashboard.sh

# 或指定其他 namespace
./openclaw/scripts/setup-grafana-dashboard.sh monitoring
```

**自动完成**：
- 创建 ConfigMap `openclaw-dashboard`（含 Dashboard JSON）
- 添加 label `grafana_dashboard=1`（Grafana sidecar 通过此 label 发现）
- Grafana sidecar 30 秒内自动导入

**验证**：

1. **检查 ConfigMap**：
   ```bash
   kubectl -n monitoring get cm openclaw-dashboard -o jsonpath='{.metadata.labels}'
   # 应输出: {"grafana_dashboard":"1"}
   ```

2. **查看 Grafana**：
   - 访问 Grafana UI
   - 左侧菜单 → **Dashboards** → 搜索 `OpenClaw`
   - 或直接访问：`<grafana-url>/d/openclaw-overview`

3. **查看 sidecar 日志**（如果未自动导入）：
   ```bash
   kubectl -n monitoring logs -l app.kubernetes.io/name=grafana -c grafana-sc-dashboard --tail=50
   ```

### 2.2 方式二：API 导入

**适用场景**：Grafana 无 sidecar，或需要直接通过 API 导入

**步骤 1：获取 Grafana 凭证**

```bash
# 方式 A：从 Secret 获取
kubectl -n monitoring get secret grafana-admin-credentials -o jsonpath='{.data.admin-password}' | base64 -d

# 方式 B：查看 HelmRelease 中的 secretRef 配置
rg -n "grafana-admin-credentials|grafana-smtp-credentials|alertmanager-config" fluxcd/configs/monitor/helmrelease.yaml
```

**步骤 2：Port-forward 到本地**

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80 &
```

**步骤 3：运行导入脚本**

```bash
export GRAFANA_URL=http://localhost:3000
export GRAFANA_USER=admin
export GRAFANA_PASS=prom-operator  # 替换为实际密码
./openclaw/scripts/setup-grafana-dashboard.sh
```

**验证**：
- 访问 `http://localhost:3000`
- 登录后 → Dashboards → OpenClaw Overview

**清理**：

```bash
# 停止 port-forward
pkill -f "port-forward.*grafana"
```

---

## 3. Alertmanager 告警接收器

### 3.1 获取 Telegram Bot Token 和 Chat ID

#### 步骤 1：创建 Bot

1. 打开 Telegram，搜索 **`@BotFather`**（官方机器人）
2. 发送 `/newbot` 命令
3. 按提示操作：
   ```
   BotFather: Alright, a new bot. How are we going to call it? Please choose a name for your bot.
   你: OpenClaw Alert Bot
   
   BotFather: Good. Now let's choose a username for your bot. It must end in `bot`.
   你: openclaw_alert_bot
   ```
4. 创建成功后，BotFather 会返回：
   ```
   Done! Congratulations on your new bot. You will find it at t.me/openclaw_alert_bot.
   
   Use this token to access the HTTP API:
   123456789:ABCdefGHIjklMNOpqrsTUVwxyz1234567890
   
   Keep your token secure and store it safely, it can be used by anyone to control your bot.
   ```
5. **复制并保存 token**：`123456789:ABCdefGHIjklMNOpqrsTUVwxyz1234567890`

#### 步骤 2：获取 Chat ID

**方式 A：私聊接收告警**

1. 在 Telegram 搜索你刚创建的 bot（如 `@openclaw_alert_bot`）
2. 点击 **Start** 或发送任意消息（如 `/start`）
3. 浏览器访问（替换 `<TOKEN>` 为你的 bot token）：
   ```
   https://api.telegram.org/bot<TOKEN>/getUpdates
   ```
   例如：
   ```
   https://api.telegram.org/bot123456789:ABCdefGHIjklMNOpqrsTUVwxyz1234567890/getUpdates
   ```
4. 返回 JSON 中找到 `"chat":{"id":987654321,...}`
5. 记录 **Chat ID**（正数）：`987654321`

**方式 B：群组接收告警**

1. 创建一个 Telegram 群组（或使用现有群组）
2. 将你的 bot 添加到群组：
   - 群组设置 → Add Members → 搜索你的 bot → 添加
   - 赋予 bot **管理员权限**（可发送消息）
3. 在群组发送任意消息（如 `@openclaw_alert_bot test`）
4. 浏览器访问 `https://api.telegram.org/bot<TOKEN>/getUpdates`
5. 返回 JSON 中找到 `"chat":{"id":-1001234567890,...}`（**负数**）
6. 记录 **Chat ID**（负数）：`-1001234567890`

#### 步骤 3：测试（可选）

用 curl 发送测试消息：

```bash
curl -X POST "https://api.telegram.org/bot<TOKEN>/sendMessage" \
  -d "chat_id=<CHAT_ID>" \
  -d "text=OpenClaw 告警测试"
```

成功后你会在 Telegram 收到消息。

### 3.2 配置 secrets.env

编辑 `openclaw/scripts/secrets.env`，添加：

```bash
# Telegram Alerting
TELEGRAM_BOT_TOKEN=123456789:ABCdefGHIjklMNOpqrsTUVwxyz1234567890
TELEGRAM_CHAT_ID=-1001234567890  # 群组用负数，私聊用正数
```

**注意**：
- `TELEGRAM_BOT_TOKEN` 已在 `openclaw-channel-keys` Secret 中（Agent 消息通道），这里是给 Alertmanager 用的
- 可以用同一个 bot，也可以创建专门的告警 bot

### 3.3 一键配置

```bash
./openclaw/scripts/setup-alertmanager.sh
```

**自动完成**：
- 创建 Secret `alertmanager-telegram`（默认创建在 `openclaw` 命名空间，需与 `AlertmanagerConfig` 同名空间）
- 创建 AlertmanagerConfig CRD（路由 `namespace=openclaw` 告警到 Telegram）
- 配置消息模板（HTML 格式）

**验证**：

1. **检查 AlertmanagerConfig**：
   ```bash
   kubectl -n openclaw get alertmanagerconfig openclaw-telegram
   ```

2. **检查 Secret**：
   ```bash
   kubectl -n openclaw get secret alertmanager-telegram
   ```

3. **查看 Alertmanager 配置**：
   - 访问 Alertmanager UI（通过 Ingress 或 port-forward）
   - Status → Config → 搜索 `openclaw-telegram`
   - 应该看到 Telegram receiver 配置

**测试告警**：

```bash
# 方式 1：删除 Pod（会触发 OpenClawPodRestarting 告警，5 分钟后发送）
kubectl -n openclaw delete pod hanbao-0

# 方式 2：手动触发测试告警（立即发送）
kubectl -n openclaw run alert-test --image=busybox --restart=Never --command -- sh -c "exit 1"
# 等待 1 分钟后删除
kubectl -n openclaw delete pod alert-test
```

成功后你会在 Telegram 收到类似消息：

```
OpenClawPodRestarting
Status: firing
alertname: OpenClawPodRestarting
namespace: openclaw
pod: hanbao-0
severity: warning

OpenClaw pod restarting frequently
Pod hanbao-0 has restarted 4 times in the last hour.
```

---

## 4. GitHub Actions CI 自动化

### 4.1 CI 做什么

`.github/workflows/openclaw-deploy.yml` 在以下文件变更时自动 apply：
- `openclaw/config/prometheus-rules.yaml`
- `openclaw/config/longhorn-backup.yaml`
- `openclaw/config/namespace-policies.yaml`

### 4.2 配置 KUBECONFIG_B64

**步骤 1：创建 ServiceAccount 和权限**

```bash
# 创建 ServiceAccount
kubectl create sa github-actions -n openclaw

# 绑定权限（仅 openclaw + longhorn-system）
kubectl create clusterrolebinding github-actions-openclaw \
  --clusterrole=edit \
  --serviceaccount=openclaw:github-actions
```

**步骤 2：生成 kubeconfig**

```bash
# 生成 token（k8s 1.24+，10 年有效期）
kubectl create token github-actions -n openclaw --duration=87600h > /tmp/github-token

# 获取集群信息
CLUSTER_NAME=$(kubectl config current-context)
CLUSTER_SERVER=$(kubectl config view -o jsonpath="{.clusters[?(@.name=='$CLUSTER_NAME')].cluster.server}")
CLUSTER_CA=$(kubectl config view --raw -o jsonpath="{.clusters[?(@.name=='$CLUSTER_NAME')].cluster.certificate-authority-data}")

# 构造 kubeconfig
cat > /tmp/github-kubeconfig.yaml <<EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: $CLUSTER_CA
    server: $CLUSTER_SERVER
  name: $CLUSTER_NAME
contexts:
- context:
    cluster: $CLUSTER_NAME
    user: github-actions
  name: github-actions@$CLUSTER_NAME
current-context: github-actions@$CLUSTER_NAME
users:
- name: github-actions
  user:
    token: $(cat /tmp/github-token)
EOF

# 验证 kubeconfig（可选）
kubectl --kubeconfig=/tmp/github-kubeconfig.yaml get ns openclaw
```

**步骤 3：Base64 编码**

```bash
# macOS
base64 -i /tmp/github-kubeconfig.yaml | pbcopy
echo "已复制到剪贴板"

# Linux
base64 -w 0 /tmp/github-kubeconfig.yaml | xclip -selection clipboard
# 或手动复制输出
base64 -w 0 /tmp/github-kubeconfig.yaml
```

**步骤 4：添加到 GitHub Secret**

1. 打开仓库：`https://github.com/womenlia/home-lab`
2. Settings → Secrets and variables → **Actions**
3. 点击 **New repository secret**
4. 填写：
   - Name: `KUBECONFIG_B64`
   - Secret: 粘贴上一步复制的 base64 字符串
5. 点击 **Add secret**

**步骤 5：测试 CI**

```bash
# 修改任意监控配置文件
echo "# test ci" >> openclaw/config/prometheus-rules.yaml
git add openclaw/config/prometheus-rules.yaml
git commit -m "test: trigger CI"
git push
```

查看 GitHub Actions：
- 仓库 → **Actions** 标签
- 应该看到 `openclaw-infra` workflow 运行
- 点击查看日志，确认 `kubectl apply` 成功

**清理临时文件**：

```bash
rm /tmp/github-token /tmp/github-kubeconfig.yaml
```

---

## 5. 完整自动化流程

### 首次部署

```bash
# 1. 安装 Operator
./openclaw/scripts/openclaw.sh install

# 2. 配置 secrets.env（填入所有 key）
vi openclaw/scripts/secrets.env

# 3. 创建 K8s Secrets
./openclaw/scripts/openclaw.sh setup-secrets

# 4. 配置 S3 备份
./openclaw/scripts/setup-backup-target.sh

# 5. 应用集群配置
./openclaw/scripts/openclaw.sh apply-infra

# 6. 部署 Agent
./openclaw/scripts/openclaw.sh create hanbao

# 7. 配置 Grafana Dashboard
./openclaw/scripts/setup-grafana-dashboard.sh

# 8. 配置 Alertmanager
./openclaw/scripts/setup-alertmanager.sh

# 9. 验证
./openclaw/scripts/openclaw.sh check
```

### 日常维护

- **Operator 升级**：`./openclaw/scripts/openclaw.sh upgrade`
- **配置变更**：修改 YAML → git push → GitHub Actions 自动 apply
- **新增 Agent**：`./openclaw/scripts/openclaw.sh create <name>`
- **备份恢复**：见 `docs/disaster-recovery.md`

---

## 6. 故障排查

| 问题 | 检查 | 解决 |
|------|------|------|
| Longhorn backup 失败 | Longhorn UI → Backup | 检查 S3 credentials，测试连接 |
| pre-update backup 卡在 `ContainerCreating` | `./openclaw/scripts/recreate-preupdate-backup-job.sh hanbao` | 将备份 Job 重建到带 `node.longhorn.io/create-default-disk=true` 的节点 |
| Grafana 未显示 Dashboard | `kubectl get cm -n monitoring` | 确认 ConfigMap 有 `grafana_dashboard=1` label |
| Alertmanager 未收到告警 | Alertmanager UI → Status | 检查 route 匹配规则，Secret 是否存在 |
| GitHub Actions 失败 | Actions 日志 | 检查 `KUBECONFIG_B64` 是否正确，token 是否过期 |

---

## 附录：secrets.env 完整模板

```bash
# Platform API Keys
SKYAPI_API_KEY=sk-sky-xxx
ALIYUN_API_KEY=sk-sp-xxx

# Messaging (optional)
TELEGRAM_BOT_TOKEN=123456:ABC...

# Tailscale (optional)
TAILSCALE_AUTHKEY=tskey-auth-xxx

# S3 Backup Target
S3_ACCESS_KEY_ID=xxx
S3_SECRET_ACCESS_KEY=xxx
S3_ENDPOINT=https://xxx.r2.cloudflarestorage.com
S3_BUCKET=openclaw-backup
S3_REGION=auto

# Telegram Alerting
TELEGRAM_CHAT_ID=-1001234567890
```

加密后提交：

```bash
./openclaw/scripts/openclaw.sh encrypt-secrets
git add openclaw/scripts/secrets.env
git commit -m "chore: update secrets"
```
