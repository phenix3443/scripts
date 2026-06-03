# k3s 集群生产级 OpenClaw 部署计划

> 分阶段指南：从 Operator 安装到记忆系统集成、监控、备份。

---

## 阶段一：安装 OpenClaw Kubernetes Operator ✅

### 1.1 前置检查 ✅

```bash
# 确认 k3s 版本 >= 1.28
k3s --version

# 确认 Helm 3 可用
helm version

# 确认集群可达
kubectl get nodes
```

### 1.2 安装 Operator ✅

Operator 支持 **amd64/arm64 多架构**，适配集群中 ARM 树莓派和 x86 节点混合环境。

```bash
./openclaw/scripts/openclaw.sh install
```

Operator 安装在 `openclaw-operator-system` 命名空间，Agent 资源在 `openclaw` 命名空间。

### 1.3 验证安装 ✅

```bash
kubectl get pods -n openclaw-operator-system
kubectl get crd | grep openclaw
```

确认 `openclawinstances.openclaw.rocks` CRD 已注册。

### 踩坑预警

- Operator 需要 K8s 1.28+，低于此版本需先升级 k3s
- Operator 安装 validating webhook，依赖集群内 DNS 正常工作
- Operator 镜像 ~50MB，树莓派节点拉取较慢，但只需在一个节点运行
- 如果 `openclaw-operator` 报 `failed to wait for ... caches to sync`、`Informer to sync` 或反复 `CrashLoopBackOff`，优先检查它所在节点的 CPU / 内存是否偏紧；当前仓库里的默认缓解方式是适度上调 operator 资源，再滚动重启

---

## 阶段二：部署 OpenClaw Agent 实例 ✅

### 2.1 创建 Namespace 和 Secrets ✅

API Key 按**平台**组织，存储在 `scripts/secrets.env`（ansible-vault 加密后提交）中：

```bash
# 编辑 secrets 文件（首次运行自动生成模板）
vi openclaw/scripts/secrets.env

# 创建 K8s Secret
./openclaw/scripts/openclaw.sh setup-secrets

# 验证 API 连通性
./openclaw/scripts/openclaw.sh test-secrets
```

当前已配置的平台：

| 平台 | 环境变量 | 可用模型 |
|------|---------|---------|
| SkyAPI | `SKYAPI_API_KEY` | Claude Opus/Sonnet/Haiku, GPT-5 |
| Aliyun Coding Plan | `ALIYUN_API_KEY` | Qwen3, Kimi K2.5, GLM-5, MiniMax |

### 2.2 关键配置决策 ✅

| 配置项 | 实际值 | 理由 |
|--------|--------|------|
| 模型配置 | `models.providers` (自定义 provider) | 使用第三方代理，非原生 API |
| 主模型 | `skyapi-claude/claude-sonnet-4-5` | 编码最优 |
| 备选模型 | `aliyun/qwen3-coder-plus`, `aliyun/qwen3.5-plus` | 成本低的 fallback |
| 存储 | 10Gi, StorageClass: longhorn | 复用现有 Longhorn，默认 2 副本冗余 |
| 资源请求 | 500m CPU / 1Gi MEM | OpenClaw 本体轻量 |
| 资源限制 | 2000m CPU / 4Gi MEM | 防止 runaway 影响其他 Pod |
| Chromium sidecar | 启用 | 浏览器自动化需额外 1-2Gi MEM |
| config.mergeMode | `merge` | Agent 运行时自我修改的配置在重启后保留 |

### 2.3 部署 Agent ✅

```bash
./openclaw/scripts/openclaw.sh create agent-primary
./openclaw/scripts/openclaw.sh status
```

当前精简部署状态（Tailscale / Mem0 / Skills 暂未启用）：
- Operator: 1/1 Running (openclaw-operator-system)
- agent-primary: 4/4 Running (openclaw)
- PVC: 10Gi Longhorn Bound
- operator 目前按更宽松的运行时缓存同步需求配置了资源，若后续改回默认值请先观察日志和节点负载

### 2.4 节点调度策略

集群混合 ARM（树莓派 4 核 7.6GB）和 x86（NUC 12 核 31GB / EQ 4 核 15GB / ME 4 核 11GB）节点。

策略：**不硬绑节点，优先调度到 x86**。Agent YAML 中已配置 `preferredDuringSchedulingIgnoredDuringExecution`，weight 80 偏好 `kubernetes.io/arch=amd64`。NUC/EQ/ME 优先，资源不足才回退到树莓派。

### 2.5 动态扩缩容

OpenClaw 是单用户应用（每用户一个实例），"动态扩容"指按需创建/销毁 Agent 实例。

**方案 A：手动管理**（适合 2-5 个固定用户）

```bash
# 从模板创建新 Agent
cp agent-template.yaml agent-alice.yaml
sed -i '' 's/AGENT_NAME/agent-alice/g' agent-alice.yaml
kubectl apply -f agent-alice.yaml

# 不需要时删除（Operator 自动备份 + 清理）
kubectl delete openclawinstance agent-alice -n openclaw
```

**方案 B：脚本化管理**（推荐，后续编写 `openclaw.sh`）

支持 `create <name>` / `delete <name>` / `list` / `status` 子命令。

**方案 C：KEDA 事件驱动**（5+ 用户时考虑）

基于消息队列深度或请求指标触发自动创建实例，当前规模不需要。

---

## 阶段三：记忆系统集成（Token 节省策略）

参考 [holly.ink 分析](https://holly.ink/archives/1007)，记忆系统可节省约 **90% 的 Token 开支**。

### 方案对比

| 维度 | Mem0 云端 | Mem0 自托管 | SuperMemory 云端 |
|------|----------|-----------|-----------------|
| 免费额度 | 1 万条记忆 / 月 1000 次检索 | 无限 | 100 万 Token / 月 1 万次搜索 |
| 运维成本 | 零 | 需维护 PG + Neo4j + FastAPI | 零 |
| 集群资源 | 无 | ~1.25 CPU / 3.5Gi MEM / 30Gi 存储 | 无 |
| 隐私 | 数据在 Mem0 云端 | 完全本地 | 数据在 SuperMemory 云端 |
| 核心能力 | 图谱记忆（知识推理） | 同云端 | 知识图谱 + 自动遗忘 |
| Pro 价格 | $19/月 | $0 | $19/月 |

### 方案 A：Mem0 云端（推荐起步）

1. 注册 https://app.mem0.ai/ 获取 API Key
2. 创建 Secret（见阶段二）
3. Agent spec 中引用 Secret 并添加 skill

```yaml
spec:
  envFrom:
    - secretRef:
        name: openclaw-mem0-keys
  skills:
    - "mem0"
```

### 方案 B：Mem0 自托管

部署 3 个组件到 k3s：

| 组件 | 资源需求 | 存储 |
|------|---------|------|
| Mem0 Server (FastAPI) | 256m CPU / 512Mi MEM | - |
| PostgreSQL + pgvector | 500m CPU / 1Gi MEM | 20Gi PVC (longhorn) |
| Neo4j | 500m CPU / 2Gi MEM | 10Gi PVC (longhorn) |

**注意**：Neo4j 内存要求高，必须调度到 NUC 或 EQ，不要跑在树莓派上。

### 方案 C：SuperMemory 云端

```yaml
spec:
  skills:
    - "supermemory"
```

### 推荐路径

1. 先用 Mem0 或 SuperMemory **云端免费版**验证效果
2. 免费额度不够或有隐私需求时再迁移到 Mem0 自托管
3. **不要同时安装两个记忆系统**，避免重复 Token 消耗

### 自我进化 Skill（可选）

安装 [self-improving skill](https://clawhub.ai/ivangdavila/self-improving) 让 Agent 从错误中学习：

```yaml
spec:
  skills:
    - "self-improving"
```

---

## 阶段四：对外访问与通道集成

### 4.1 Tailscale 内网访问（推荐首选）

集群已部署 Tailscale，Operator 原生支持：

```yaml
spec:
  tailscale:
    enabled: true
    mode: serve
    authKeySecretRef:
      name: tailscale-authkey
    hostname: agent-primary
    authSSO: true
```

访问地址：`https://agent-primary.<tailnet>.ts.net`

### 4.2 Cloudflare Tunnel（可选公网访问）

复用现有 Cloudflare Tunnel，在 Zero Trust 中添加：

```yaml
hostname: openclaw.panghuli.tech
service: http://agent-primary.openclaw.svc.cluster.local:18789
```

**必须启用 Cloudflare Access 策略限制访问**。已有 13.5 万 OpenClaw 实例因直接暴露公网被攻击。WebSocket headers（`Upgrade` / `Connection`）必须透传。

### 4.3 消息通道

通过环境变量自动启用，将 Bot Token 添加到 `openclaw-channel-keys` Secret 即可。

---

## 阶段五：监控与安全加固

### 5.1 Prometheus + Grafana

Operator ServiceMonitor 与现有 kube-prometheus-stack 集成（agent YAML 已配置）。

Operator 自带 Grafana Dashboard，关键指标：
- `openclaw_reconcile_total` / `openclaw_reconcile_duration_seconds`
- `openclaw_instance_phase`
- 容器级 CPU/MEM 使用率

### 5.2 安全 Checklist

Operator 默认已包含：
- [x] UID 1000 非 root 运行
- [x] 所有 Linux capabilities 已 drop
- [x] seccomp RuntimeDefault
- [x] 只读根文件系统
- [x] default-deny NetworkPolicy（仅 DNS + HTTPS 出站）
- [x] Validating webhook 阻止 root 运行

额外建议：
- [ ] 定期更新 OpenClaw 版本（autoUpdate 已配置）
- [ ] 审计 ClawHub skill（已有 341 个恶意 skill 被发现）
- [ ] 配置 S3 备份

---

## 阶段六：备份与灾难恢复

实操步骤与场景说明见 **[disaster-recovery.md](disaster-recovery.md)**。

### 6.1 Longhorn 快照与异地备份

Git 中维护的 RecurringJob：`openclaw/config/longhorn-backup.yaml`（`openclaw.sh apply-infra` 或手动 `kubectl apply`）。

- **快照**：`openclaw-snapshot`（每 6h，保留 4）
- **异地备份**：`openclaw-daily-backup`（每日 02:00，保留 3）— 需先在 Longhorn UI 配置 **Backup Target**（S3 兼容），否则 backup 任务会失败

### 6.2 Operator 级备份/恢复

Agent 删除时自动备份到 S3，恢复：

```yaml
spec:
  restoreFrom: "s3://bucket/path/to/backup.tar.gz"
```

以当前 Operator CRD 文档为准校验 `restoreFrom` 字段。

---

## 资源预算汇总

| 组件 | CPU (请求/限制) | MEM (请求/限制) | 存储 | 调度建议 |
|------|----------------|----------------|------|---------|
| Operator | 100m/200m | 128Mi/256Mi | - | 任意节点 |
| Agent x1 (含 Chromium) | 750m/3000m | 1.5Gi/6Gi | 10Gi | 优先 x86 |
| Agent x5 (含 Chromium) | 3750m/15000m | 7.5Gi/30Gi | 50Gi | 分散调度 |
| Mem0 自托管 (可选) | 1250m/3000m | 3.5Gi/8Gi | 30Gi | NUC/EQ |

x86 节点池（NUC 12 核 31GB + EQ 4 核 15GB + ME 4 核 11GB = **20 核 / 57GB RAM**），5 个 Agent + Mem0 自托管资源充足。

---

## 常见踩坑清单

| # | 问题 | 说明 |
|---|------|------|
| 1 | k3s 版本兼容性 | Operator 需 K8s 1.28+，先检查 `k3s --version` |
| 2 | ARM/x86 混合调度 | Chromium sidecar 需确认 arm64 镜像可用 |
| 3 | mDNS 不工作 | K8s 网络中 mDNS 不可用，Operator 通过 auto-generated gateway token 解决 |
| 4 | 公网暴露风险 | 绝不直接暴露 Agent 到公网，必须经 Tailscale 或 Cloudflare Access |
| 5 | ClawHub 恶意 skill | 仅安装经审计的 skill，优先用 `@anthropic/` 官方 skill |
| 6 | Token 成本飙升 | 未配记忆系统前重度使用月账单可达 $600+，先配好 Mem0/SuperMemory |
| 7 | Longhorn 副本数 | OpenClaw workspace 数据用默认 2 副本即可 |
| 8 | Neo4j 内存 | 自托管 Mem0 时 Neo4j 最低需 2GB heap，不要调度到树莓派 |
| 9 | **Clash fake-ip + CoreDNS** | 节点运行 Clash fake-ip 模式时，CoreDNS forward 到 `/etc/resolv.conf` 会返回 198.18.x.x 不可路由地址。**修复**：CoreDNS forward 改为 `8.8.8.8 1.1.1.1` |
| 10 | **`llmConfig` 无效** | OpenClaw 不认识 `llmConfig` 配置键，自定义 LLM provider 必须用 `models.providers`，模型引用格式为 `provider/model`（如 `skyapi-claude/claude-sonnet-4-5`） |
| 11 | **Skills 安装需网络** | `init-skills` 容器通过 `npx` 下载 skill 包，需要访问 `registry.npmjs.org`。DNS 或网络不通会导致 Pod 无限卡在 init 阶段 |

---

## 参考链接

- [OpenClaw 官方文档](https://clawdocs.org/getting-started/introduction/)
- [OpenClaw Kubernetes Operator](https://github.com/OpenClaw-rocks/k8s-operator)
- [Operator 部署指南](https://openclaw.rocks/blog/deploy-openclaw-kubernetes)
- [Mem0 文档](https://docs.mem0.ai/)
- [SuperMemory 文档](https://console.supermemory.ai/)
- [Token 节省最佳实践](https://holly.ink/archives/1007)
