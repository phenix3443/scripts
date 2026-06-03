#!/usr/bin/env bash
#
# setup-alertmanager.sh - Configure Alertmanager receiver for OpenClaw alerts
#
# Prerequisites:
#   - Prometheus/Alertmanager installed (kube-prometheus-stack or standalone)
#   - TELEGRAM_BOT_TOKEN in secrets.env (or pass via env)
#
# Usage:
#   ./setup-alertmanager.sh
#
# This repo expects the Telegram secret and AlertmanagerConfig to live in openclaw.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_FILE="${SCRIPT_DIR}/secrets.env"
VAULT_PASS_FILE="${SCRIPT_DIR}/../../ansible/.vault_pass"
AM_NS="openclaw"

log_info()  { echo "[INFO] $*"; }
log_ok()    { echo "[OK]   $*"; }
log_warn()  { echo "[WARN] $*" >&2; }
log_err()   { echo "[ERR]  $*" >&2; exit 1; }

# Source secrets
if [[ -f "$SECRETS_FILE" ]]; then
    if head -1 "$SECRETS_FILE" 2>/dev/null | grep -q '^\$ANSIBLE_VAULT;'; then
        [[ -f "$VAULT_PASS_FILE" ]] || log_err "Vault password file not found: $VAULT_PASS_FILE"
        tmp=$(mktemp)
        trap "rm -f '$tmp'" EXIT
        ansible-vault decrypt "$SECRETS_FILE" --vault-password-file "$VAULT_PASS_FILE" --output "$tmp"
        # shellcheck source=/dev/null
        source "$tmp"
    else
        # shellcheck source=/dev/null
        source "$SECRETS_FILE"
    fi
fi

TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:--1001234567890}"

if [[ -z "$TELEGRAM_BOT_TOKEN" ]]; then
    log_warn "TELEGRAM_BOT_TOKEN not set in secrets.env"
    log_info "This script will create AlertmanagerConfig CRD, but you need to:"
    log_info "  1. Get bot token from @BotFather"
    log_info "  2. Add to secrets.env: TELEGRAM_BOT_TOKEN=123456:ABC..."
    log_info "  3. Get chat ID: send message to bot, visit https://api.telegram.org/bot<TOKEN>/getUpdates"
    log_info "  4. Re-run this script"
    exit 0
fi

log_info "Configuring Alertmanager receiver for OpenClaw alerts..."
log_info "  Secret namespace: $AM_NS"
log_info "  Chat ID: $TELEGRAM_CHAT_ID"

# Create Secret for Telegram bot token
kubectl -n "$AM_NS" delete secret alertmanager-telegram 2>/dev/null || true
kubectl -n "$AM_NS" create secret generic alertmanager-telegram \
    --from-literal=bot-token="$TELEGRAM_BOT_TOKEN"

log_ok "Secret alertmanager-telegram created"

# Create AlertmanagerConfig CRD (if using prometheus-operator)
kubectl apply -f - <<EOF
apiVersion: monitoring.coreos.com/v1alpha1
kind: AlertmanagerConfig
metadata:
  name: openclaw-telegram
  namespace: openclaw
  labels:
    release: kube-prometheus-stack
spec:
  route:
    receiver: openclaw-telegram
    matchers:
      - name: namespace
        value: openclaw
        matchType: "="
    continue: true
  receivers:
    - name: openclaw-telegram
      telegramConfigs:
        - botToken:
            name: alertmanager-telegram
            key: bot-token
          chatID: ${TELEGRAM_CHAT_ID}
          sendResolved: true
          parseMode: HTML
          message: |
            <b>{{ .GroupLabels.alertname }}</b>
            {{ range .Alerts }}
            Status: {{ .Status }}
            {{ range .Labels.SortedPairs }}{{ .Name }}: {{ .Value }}
            {{ end }}
            {{ .Annotations.summary }}
            {{ .Annotations.description }}
            {{ end }}
EOF

log_ok "AlertmanagerConfig openclaw-telegram created"

echo ""
log_ok "Alertmanager receiver setup complete!"
echo "  Test: kubectl -n openclaw delete pod hanbao-0 (will trigger PodRestarting alert)"
echo "  Check: Alertmanager UI → Status → Config"
