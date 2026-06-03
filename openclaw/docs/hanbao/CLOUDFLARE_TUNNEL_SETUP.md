# OpenClaw Cloudflare Tunnel 配置指南

> 通过 Cloudflare Tunnel 安全访问 OpenClaw Agent

---

## ✅ 当前状态

| 组件 | 状态 | 说明 |
|------|------|------|
| Ingress | ✅ 已配置 | openclaw.panghuli.tech |
| Nginx Ingress Controller | ✅ 运行中 | ingress-nginx namespace |
| OpenClaw Agent | ✅ 运行中 | hanbao (2/2 containers) |
| NetworkPolicy | ✅ 已启用 | 允许 ingress-nginx + 出站 80/443 |

---

## 📋 已完成的配置

### 1. Ingress 配置

Ingress 由 **`openclaw/scripts/openclaw.sh`** 在 `create <agent-name>` 时通过内嵌 manifest 下发（仓库内**没有**静态 `config/ingress.yaml`）。主机名为 `<agent-name>.<INGRESS_DOMAIN>`（默认 `INGRESS_DOMAIN=panghuli.tech`）。

等价 YAML 结构如下（与脚本生成内容一致；含 `limit-rps` 等注解时以脚本为准）：

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: agent-primary-ingress
  namespace: openclaw
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/limit-rps: "30"
    nginx.ingress.kubernetes.io/proxy-connect-timeout: "30"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-http-version: "1.1"
    nginx.ingress.kubernetes.io/websocket-services: "agent-primary"
    nginx.ingress.kubernetes.io/proxy-buffering: "off"
    nginx.ingress.kubernetes.io/proxy-request-buffering: "off"
spec:
  ingressClassName: nginx
  rules:
    - host: openclaw.panghuli.tech
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: agent-primary
                port:
                  number: 18789  # Service port (maps to targetPort 18790)
```

**关键配置**：
- ✅ WebSocket 支持（OpenClaw gateway 需要）
- ✅ 扩展超时（3600 秒，支持长时间 AI 操作）
- ✅ 禁用代理缓冲（流式响应）
- ✅ SSL 重定向禁用（Cloudflare Tunnel 处理 HTTPS）
- ✅ `limit-rps` 应用层限流（可按需调大/调小）

### 2. Service 端口映射

```
Service Port 18789 → Target Port 18790 (gateway-proxy container)
                  ↓
              Pod IP:18790 → nginx proxy → 127.0.0.1:18789 (openclaw container)
```

### 3. NetworkPolicy 已修复

NetworkPolicy 已启用，通过 `allowedIngressNamespaces` 允许 `ingress-nginx` namespace 入站流量：

```yaml
security:
  networkPolicy:
    enabled: true
    allowedIngressNamespaces:
      - ingress-nginx
    additionalEgress:
      - to:
          - ipBlock:
              cidr: 0.0.0.0/0
        ports:
          - port: 80
            protocol: TCP
          - port: 443
            protocol: TCP
```

---

## 🌐 Cloudflare Tunnel 配置步骤

### 方式 1：通过 Cloudflare Zero Trust Dashboard（推荐）

1. **登录 Cloudflare Zero Trust**
   - 访问 https://one.dash.cloudflare.com/
   - 选择你的账户

2. **添加公共主机名**
   - 导航到 `Access` → `Tunnels`
   - 选择你的现有 Tunnel（或创建新的）
   - 点击 `Public Hostname` → `Add a public hostname`

3. **配置主机名**
   ```
   Subdomain: openclaw
   Domain: panghuli.tech
   Path: （留空）
   
   Service:
     Type: HTTP
     URL: ingress-nginx-controller.ingress-nginx.svc.cluster.local:80
   
   Additional application settings:
     HTTP Host Header: openclaw.panghuli.tech
   ```

4. **保存配置**
   - 点击 `Save hostname`
   - 等待 DNS 记录自动创建（约 1-2 分钟）

### 方式 2：通过 cloudflared CLI

如果你有 cloudflared CLI 访问权限：

```bash
# 添加 ingress 规则到 Tunnel 配置
cat >> /path/to/tunnel-config.yaml <<EOF
ingress:
  - hostname: openclaw.panghuli.tech
    service: http://ingress-nginx-controller.ingress-nginx.svc.cluster.local:80
    originRequest:
      httpHostHeader: openclaw.panghuli.tech
      noTLSVerify: false
EOF

# 重启 cloudflared
kubectl rollout restart deployment/cloudflared -n cloudflare
```

---

## 🔒 配置 Cloudflare Access 策略（重要！）

**⚠️  强烈建议配置访问策略，避免未授权访问！**

1. **创建 Access Application**
   - 导航到 `Access` → `Applications` → `Add an application`
   - 选择 `Self-hosted`

2. **配置应用**
   ```
   Application name: OpenClaw Agent
   Session Duration: 24 hours
   Application domain: openclaw.panghuli.tech
   ```

3. **添加策略**
   ```
   Policy name: Allow specific users
   Action: Allow
   
   Include:
     - Emails: your-email@example.com
     或
     - Email domain: @yourcompany.com
   ```

4. **保存并测试**
   - 访问 https://openclaw.panghuli.tech
   - 应该会跳转到 Cloudflare Access 登录页面
   - 登录后才能访问 OpenClaw UI

---

## ✅ 验证访问

### 1. 集群内部测试

```bash
# 创建测试 Pod
kubectl run curl-test -n openclaw --image=curlimages/curl:latest --restart=Never --command -- sleep 600

# 测试 Ingress
kubectl exec -n openclaw curl-test -- curl -I -H "Host: openclaw.panghuli.tech" \
  http://ingress-nginx-controller.ingress-nginx.svc.cluster.local:80/

# 预期输出：HTTP/1.1 200 OK

# 清理
kubectl delete pod curl-test -n openclaw
```

### 2. 公网访问测试

配置 Cloudflare Tunnel 后：

```bash
# 测试 DNS 解析
dig openclaw.panghuli.tech

# 测试 HTTPS 访问
curl -I https://openclaw.panghuli.tech

# 或浏览器访问
open https://openclaw.panghuli.tech
```

---

## 🔧 故障排查

### 问题 1：502 Bad Gateway

**可能原因**：
1. NetworkPolicy 阻止流量
2. Service 端口配置错误
3. Pod 未就绪

**排查步骤**：
```bash
# 1. 检查 Pod 状态
kubectl get pods -n openclaw

# 2. 检查 Service Endpoints
kubectl get endpoints agent-primary -n openclaw

# 3. 检查 NetworkPolicy
kubectl get networkpolicy -n openclaw

# 4. 查看 Ingress Controller 日志
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=50 | grep openclaw
```

### 问题 2：WebSocket 连接失败

**解决方案**：
- 确认 Ingress annotations 包含 WebSocket 支持
- 确认 Cloudflare Tunnel 配置允许 WebSocket（默认启用）

### 问题 3：Cloudflare Access 循环重定向

**解决方案**：
- 检查 Access 策略是否正确
- 确认 Cookie 设置允许第三方 Cookie
- 清除浏览器缓存和 Cookie

---

## 📊 架构图

```
Internet
    ↓
Cloudflare Tunnel (HTTPS)
    ↓
Cloudflare Edge (SSL Termination + Access Policy)
    ↓
Cloudflared Pod (k3s cluster)
    ↓
Nginx Ingress Controller (ingress-nginx namespace)
    ↓
agent-primary Service (openclaw namespace, port 18789)
    ↓
agent-primary-0 Pod (gateway-proxy container, port 18790)
    ↓
nginx reverse proxy (127.0.0.1:18789)
    ↓
openclaw container (OpenClaw Agent)
```

---

## 🔐 安全建议

1. **启用 Cloudflare Access**
   - ✅ 必须配置，避免公网直接访问
   - ✅ 使用邮箱白名单或 SSO 集成

2. **NetworkPolicy**
   - ✅ 已启用，允许 ingress-nginx 入站 + 出站 80/443
   - Operator 自动管理，无需手动维护

3. **监控访问日志**
   ```bash
   # 查看 Ingress 访问日志
   kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx -f | grep openclaw
   
   # 查看 OpenClaw 日志
   kubectl logs -n openclaw agent-primary-0 -c openclaw -f
   ```

4. **定期更新**
   - OpenClaw Agent 已配置自动更新（每 24h 检查）
   - Cloudflare Tunnel 建议固定版本，手动更新

---

## 📝 后续优化任务

- [x] 修复 NetworkPolicy 规则（allowedIngressNamespaces: ingress-nginx）
- [x] 配置 Cloudflare Access 策略
- [x] 启用 Prometheus 监控告警（PrometheusRule openclaw-alerts）
- [x] 配置 Longhorn 定时快照（每 6h，保留 4 份）
- [x] 启用 LanceDB 向量记忆系统（替代 Mem0）
- [x] 配置 Tailscale（agent-primary 已启用）
- [x] 启用 selfConfigure（Agent 可自主安装 skills）
- [ ] 接入消息通道（Telegram/Discord，需 Bot Token）

---

## 📚 相关文档

- [OpenClaw 部署验证报告](./DEPLOYMENT_VERIFICATION.md)
- [OpenClaw 部署计划](./deploy-plan.md)
- [Ingress 配置](../../k3s/docs/ingress.md)
- [Cloudflare Tunnel 文档](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)

---

## 🆘 获取帮助

如遇到问题，请提供以下信息：

```bash
# 收集诊断信息
./openclaw/scripts/openclaw.sh diagnose > openclaw-diagnostics.txt

# 包括：
# - Operator 状态和日志
# - Agent 实例状态
# - Pod 事件
# - NetworkPolicy 配置
# - Ingress 配置
```
