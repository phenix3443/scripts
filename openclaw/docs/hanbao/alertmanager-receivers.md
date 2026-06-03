# Routing OpenClaw alerts to Alertmanager receivers

`openclaw/config/prometheus-rules.yaml` defines `PrometheusRule` objects in namespace `openclaw` with labels `severity: critical|warning`. Alerts only help if **Alertmanager** forwards them to a receiver (email, Slack, Telegram, Bark webhook, etc.).

Your cluster may use:

- **Standalone Prometheus** Helm chart (`prometheus/values.yaml` in this repo) — configure `alertmanager.config.route` and `receivers` there, or
- **kube-prometheus-stack** — configure receivers in the chart values or UI.

## Option A: Child route by namespace (Prometheus Helm `values`)

Add a route that matches `namespace="openclaw"` (or `alertname` prefix `OpenClaw`) before the default receiver:

```yaml
alertmanager:
  config:
    route:
      receiver: email
      routes:
        - matchers:
            - namespace="openclaw"
          receiver: telegram-openclaw
          continue: true
    receivers:
      - name: telegram-openclaw
        telegram_configs:
          - bot_token: "<BOT_TOKEN>"
            chat_id: <CHAT_ID>
            send_resolved: true
```

Store `bot_token` in a Kubernetes Secret and reference it via `alertmanager` chart’s `extraSecretMounts` / templating if your chart supports it; avoid committing tokens.

## Option B: Telegram via `AlertmanagerConfig` CRD (prometheus-operator)

If Alertmanager is managed by prometheus-operator and **AlertmanagerConfig** is enabled with a namespace selector, apply a namespaced config in `monitoring` or `openclaw` per your installation docs.

Example skeleton (API version and labels must match your operator — verify with `kubectl api-resources | grep -i alertmanager`):

```yaml
apiVersion: monitoring.coreos.com/v1alpha1
kind: AlertmanagerConfig
metadata:
  name: openclaw-routes
  namespace: openclaw
  labels:
    release: kube-prometheus-stack
spec:
  route:
    receiver: telegram
    matchers:
      - name: namespace
        value: openclaw
        matchType: "="
  receivers:
    - name: telegram
      telegramConfigs:
        - botToken:
            secretKeyRef:
              name: alertmanager-telegram
              key: bot-token
          chatID: 0
          sendResolved: true
```

Create `alertmanager-telegram` in the same namespace as the `AlertmanagerConfig` object (`openclaw` in this repo), with key `bot-token`, and adjust `chatID`.

## Option C: Bark / generic webhook

Use `webhook_configs` in a dedicated receiver and point `url` to Bark or an internal bridge.

## Verification

1. In Alertmanager UI, **Status → Config** shows active routes
2. Fire a test alert or temporarily lower a rule’s `for:` duration
3. Confirm notification delivery

See also: `k3s/docs/alerting.md` (repository root).
