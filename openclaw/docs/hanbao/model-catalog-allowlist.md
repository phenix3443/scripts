# OpenClaw 模型目录白名单

> 适用于通过 Kubernetes Operator 部署的 OpenClaw 实例。

---

## 背景

在 OpenClaw `2026.4.21` 上，Web 控制台里的模型选择器不是直接读取 `models.providers`，而是通过网关 RPC `models.list` 获取模型目录。

如果实例配置里**没有**声明 `agents.defaults.models`，`models.list` 会退回到 `allowAny=true`，把 OpenClaw 内置模型 catalog 一起返回给前端。

这会表现为：

- 你明明只配置了少量 provider / model
- Web 界面却出现大量 `openrouter`、`amazon-bedrock`、`opencode` 等内置 provider
- `agents.defaults.model.primary` / `fallbacks` 正常，但它们**不会限制**模型选择器列表

---

## 根因

`models.list` 的允许列表逻辑依赖 `agents.defaults.models`：

- `agents.defaults.models` 有值：只返回允许列表中的模型
- `agents.defaults.models` 为空：返回整份内置 catalog

因此下面这两类配置**不够**：

- 只写 `models.providers`
- 只写 `agents.defaults.model.primary` 和 `fallbacks`

要限制 Web 里的模型列表，必须额外配置 `agents.defaults.models`。

---

## 正确写法

`agents.defaults.models` 是一个对象，key 必须是完整的 `provider/model`，value 可以是空对象：

```yaml
spec:
  config:
    raw:
      models:
        mode: replace
        providers:
          aliyun:
            baseUrl: "https://coding.dashscope.aliyuncs.com/v1"
            apiKey: "${ALIYUN_API_KEY}"
            api: openai-completions
            models:
              - id: qwen3.5-plus
                name: Qwen3.5 Plus
              - id: qwen3-coder-plus
                name: Qwen3 Coder Plus
      agents:
        defaults:
          model:
            primary: "aliyun/qwen3.5-plus"
            fallbacks:
              - "aliyun/qwen3-coder-plus"
          models:
            "aliyun/qwen3.5-plus": {}
            "aliyun/qwen3-coder-plus": {}
```

要点：

- `models.providers` 定义 provider 和模型元数据
- `agents.defaults.model.primary/fallbacks` 定义默认选型
- `agents.defaults.models` 定义 Web / `/model` 可见的允许列表

三者职责不同，不能互相替代。

---

## 排查方法

### 1. 先看运行时配置

```bash
kubectl exec -n openclaw <pod> -c openclaw -- \
  sed -n '1,220p' /home/openclaw/.openclaw/openclaw.json
```

确认是否存在：

- `agents.defaults.models`
- `models.mode: replace` 或 `merge`
- 实际 `models.providers`

### 2. 直接看网关返回的模型目录

前端实际消费的是 `models.list` 返回值，不是原始 YAML。

如果 `models.list` 返回很多内置 provider，而 `openclaw.json` 里没有对应 provider，优先检查：

- `agents.defaults.models` 是否为空
- 是否错误依赖了 `primary` / `fallbacks` 来限制目录

### 3. 验证修复结果

修复后应当重新检查：

- Pod `2/2 Ready`
- `readyz` 返回 `200`
- `models.list` 只返回预期 provider / model

---

## 本仓库里的已知实例

- `hanbao`：已通过 `openclaw/config/hanbao.yaml` 补齐 `agents.defaults.models`
- `agent-team`：已通过 `fluxcd/configs/agent-team/agent-team.yaml` 补齐 `agents.defaults.models`

---

## 经验结论

如果你看到“我没配置的模型”：

1. 不要先怀疑前端缓存
2. 先抓 `models.list`
3. 再检查 `agents.defaults.models`

在当前版本下，这通常不是前端问题，而是**后端模型目录 allowlist 缺失**。
