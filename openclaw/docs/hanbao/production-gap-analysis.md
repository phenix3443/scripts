# OpenClaw 生产级就绪度分析

> 基于当前部署状态的差距分析，按优先级排列待补齐项。

---

## 已完成 (✅)

| 类别 | 已实现 |
|------|--------|
| Operator 管理 | Helm 安装 + CRD 注册 |
| Agent 部署 | agent-primary（5/5 Running），含 Chromium sidecar |
| 密钥管理 | ansible-vault 加密 + K8s Secret |
| 网络访问 | Ingress + Cloudflare Tunnel + Tailscale |
| 安全加固 | NetworkPolicy、非 root、drop all capabilities、seccomp |
| 监控告警 | ServiceMonitor + 7 条 PrometheusRule |
| 本地快照 | Longhorn 每 6h，保留 4 份 |
| 自动更新 | autoUpdate + rollback |
| 向量记忆 | LanceDB auto-recall/capture |
| 管理脚本 | openclaw.sh 全生命周期 |

---

## 缺失项

### P0 - 关键（数据安全 / 服务可靠性）

#### 1. 异地备份未启用

`longhorn-backup.yaml` 的 backup 任务处于注释状态，当前只有本地快照。本地快照在节点磁盘故障时无法恢复。

**行动**：配置 S3 备份 target（MinIO 或 Cloudflare R2），启用 daily backup，取消注释 `openclaw-daily-backup` RecurringJob。

#### 2. init 容器硬编码 amd64 架构

节点调度是 `preferredDuringScheduling`（软约束），Agent 可能被调度到 ARM 节点，但 init container 只下载 x86 二进制（jq、rg、gh、ffmpeg）。

**行动**：二选一：
- **方案 A**：改为 `requiredDuringScheduling` 硬约束绑定 amd64
- **方案 B**：init container 中检测 `uname -m`，动态选择 amd64/arm64 下载 URL

推荐方案 A，因为 Chromium sidecar 也依赖 amd64。

#### 3. 告警通知无接收端

PrometheusRule 定义了 7 条告警规则，但没有配置 AlertManager receiver。告警触发后无人知道。

**行动**：配置 AlertManager 接收器（Telegram Bot webhook 或 Bark），将 `severity: critical` 和 `severity: warning` 路由到不同通道。

---

### P1 - 重要（运维效率 / 安全合规）

#### 4. 无灾难恢复 runbook

没有文档化的恢复流程。deploy-plan.md 提到 S3 恢复（`spec.restoreFrom`），但没有实操步骤。

**行动**：编写 `docs/disaster-recovery.md`，覆盖场景：
- Agent Pod 被驱逐后重建
- PVC 数据损坏 → 从 Longhorn 快照恢复
- 整集群重建 → 从 S3 备份恢复

#### 5. Operator 无升级命令

`openclaw.sh` 有 `install`/`uninstall`，但没有 `upgrade` 命令。

**行动**：添加 `upgrade` 子命令：

```bash
cmd_upgrade() {
    ensure_helm
    log_info "Upgrading OpenClaw Operator..."
    helm upgrade "$OPERATOR_RELEASE" "$OPERATOR_CHART" \
        --namespace "$OPERATOR_NS" --reuse-values
    log_ok "Operator upgraded"
}
```

#### 6. 无 PodDisruptionBudget

节点维护（`kubectl drain`）时，Agent Pod 可能被直接驱逐。

**行动**：添加 PDB 配置：

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: agent-primary-pdb
  namespace: openclaw
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: agent-primary
```

#### 7. 消息通道未接入

agent-primary.yaml 中 `openclaw-channel-keys` secretRef 仍处于注释状态。

**行动**：
1. 在 secrets.env 中填入 `TELEGRAM_BOT_TOKEN`
2. 运行 `openclaw.sh setup-secrets`
3. 取消 agent-primary.yaml 中的注释
4. `kubectl apply` 生效

#### 8. 无资源配额保护

`openclaw` namespace 没有 ResourceQuota / LimitRange。selfConfigure 允许 Agent 自主修改配置，若失控可能影响集群。

**行动**：添加 namespace 资源配额：

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: openclaw-quota
  namespace: openclaw
spec:
  hard:
    requests.cpu: "8"
    requests.memory: 16Gi
    persistentvolumeclaims: "10"
```

---

### P2 - 建议（可观测性 / 自动化 / 可维护性）

#### 9. 无 Grafana Dashboard

有 PrometheusRule 但没有 Grafana Dashboard JSON，缺少可视化面板。

**行动**：创建 `config/grafana-dashboard.json`，包含 Agent 状态、CPU/MEM 趋势、PVC 使用率面板。

#### 10. 无集中日志

`openclaw.sh logs` 是 `kubectl logs` 包装，Pod 重启后日志丢失。

**行动**：接入 Loki 或现有日志栈，配置 Pod 日志持久化。

#### 11. 无 CI/CD 自动部署

clash 项目有 GitHub Actions 自动部署，OpenClaw 配置更新完全手工。

**行动**：添加 `.github/workflows/openclaw-deploy.yml`，在 `config/*.yaml` 变更时自动 apply。

#### 12. 文档不一致

- README 引用 `config/ingress.yaml`，但该文件不存在（由脚本动态生成）
- `hanbao.yaml` 未在文档中说明
- 文件结构列表与实际不符

**行动**：更新 README，移除 `ingress.yaml` 引用，补充 `hanbao.yaml` 说明。

#### 13. secrets.local.env 安全隐患

`scripts/secrets.local.env` 含有占位符格式的 key，应确认被 `.gitignore` 排除。

#### 14. Ingress 无速率限制

Ingress 配置没有 `nginx.ingress.kubernetes.io/limit-rps` 注解，缺少应用层限流。

#### 15. API Token 成本无监控

deploy-plan.md 提到月账单可达 $600+，但没有 Token 消耗指标或预算告警。

---

## 优先行动计划

| 优先级 | 行动 | 预估工作量 |
|--------|------|-----------|
| P0 | 配置 Longhorn S3 backup target，启用 daily backup | 1h |
| P0 | init container 加入架构检测 or 硬约束 amd64 调度 | 30min |
| P0 | 配置 AlertManager receiver（Telegram webhook） | 1h |
| P1 | 编写灾难恢复文档 | 1h |
| P1 | openclaw.sh 添加 `upgrade` 命令 | 30min |
| P1 | 添加 PDB + ResourceQuota | 30min |
| P1 | 启用消息通道（取消注释 + 配置 Bot Token） | 30min |
| P2 | 添加 Grafana Dashboard | 1h |
| P2 | GitHub Actions 自动部署 | 1h |
| P2 | 修正文档不一致 | 30min |

**总体评估**：基础架构成熟度约 **70%**，核心运行能力完备，P0 项（异地备份、架构兼容、告警通知）建议优先补齐。

---

## 仓库内已落实（持续演进）

| 原条目 | 说明 |
|--------|------|
| P0 异地备份 | `longhorn-backup.yaml` 启用 `openclaw-daily-backup`；须在 Longhorn 配置 S3 target |
| P0 amd64 | `agent-primary.yaml` 使用 `requiredDuringScheduling` 绑定 amd64 |
| P0 告警接收 | `docs/alertmanager-receivers.md` 给出 Alertmanager 路由与 Telegram 示例 |
| P1 DR runbook | `docs/disaster-recovery.md` |
| P1 `upgrade` | `openclaw.sh upgrade` |
| P1 PDB | Operator 默认协调 PDB；`agent-primary` 显式 `availability.podDisruptionBudget.enabled` |
| P1 ResourceQuota | `config/namespace-policies.yaml` + `apply-infra` |
| P1 消息通道 | `openclaw-channel-keys` 默认创建；`agent-primary` / `hanbao` 引用 Secret |
| P2 Grafana | `config/grafana/openclaw-overview.json` |
| P2 CI | `.github/workflows/openclaw-deploy.yml`（需 `KUBECONFIG_B64`） |
| P2 文档 | README / CLOUDFLARE_TUNNEL 修正；`ingress` 由脚本生成 |
| P2 Ingress 限流 | `openclaw.sh` 生成 Ingress 带 `limit-rps` |
| P13 `secrets.local.env` | 仓库 `.gitignore` 已含 `*.local.env` |
| P15 API 成本 | `prometheus-rules.yaml` 尾部注释说明用控制台/自定义指标 |
| P10 集中日志 | 仍为建议项；可接 Loki 等，未改集群 |
