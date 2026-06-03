#!/usr/bin/env bash
#
# openclaw.sh - OpenClaw Agent lifecycle management on k3s
#
# Manages the full lifecycle of OpenClaw agents via the Kubernetes Operator:
#   - Operator install/uninstall (Helm)
#   - Secrets management (API keys, channels, memory, Tailscale)
#   - Agent instance CRUD (create from template, delete with backup)
#   - Diagnostics (status, logs, port-forward, connectivity checks)
#
# Secrets are stored in scripts/secrets.env (ansible-vault encrypted in git).
# Template: scripts/secrets.template.env
# Agent config: config/<agent-name>.yaml, config/agent-template.yaml
#
# Dependencies: kubectl, helm (auto-installed), bash 4+
# Optional: ansible-vault (for encrypt/decrypt-secrets)
#
# Examples:
#   ./openclaw.sh install                  # Install Operator
#   ./openclaw.sh upgrade                  # Upgrade Operator (helm reuse-values)
#   ./openclaw.sh apply-infra              # Apply monitoring + Longhorn + quotas
#   ./openclaw.sh setup-secrets            # Create K8s secrets
#
# Automation scripts (see docs/automation-setup.md):
#   ./scripts/setup-backup-target.sh       # Configure Longhorn S3 backup (R2/B2/MinIO)
#   ./scripts/setup-grafana-dashboard.sh   # Auto-import Grafana dashboard
#   ./scripts/setup-alertmanager.sh        # Configure Telegram alerting
#   ./openclaw.sh test-secrets             # Verify LLM API keys
#   ./openclaw.sh test-connectivity        # Verify Telegram + S3 (see scripts/test-connectivity.sh)
#   ./openclaw.sh create hanbao            # Deploy agent + Ingress
#   ./openclaw.sh forward hanbao           # Access UI on localhost:18789

set -euo pipefail

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENCLAW_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_DIR="${OPENCLAW_DIR}/config"
SECRETS_FILE="${SCRIPT_DIR}/secrets.env"
VAULT_PASS_FILE="${OPENCLAW_DIR}/../ansible/.vault_pass"

NAMESPACE="${NAMESPACE:-openclaw}"
INGRESS_DOMAIN="${INGRESS_DOMAIN:-panghuli.tech}"
OPERATOR_NS="openclaw-operator-system"
OPERATOR_RELEASE="openclaw-operator"
OPERATOR_CHART="oci://ghcr.io/openclaw-rocks/charts/openclaw-operator"

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

log_info()  { echo "[INFO] $*"; }
log_ok()    { echo "[OK]   $*"; }
log_warn()  { echo "[WARN] $*" >&2; }
log_err() {
    for line in "$@"; do
        echo "[ERR]  $line" >&2
    done
    exit 1
}

# ---------------------------------------------------------------------------
# Prerequisite helpers
# ---------------------------------------------------------------------------

ensure_helm() {
    if command -v helm >/dev/null 2>&1; then return 0; fi
    log_info "Helm not found, installing..."
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    command -v helm >/dev/null 2>&1 || log_err "Helm install failed"
    log_ok "Helm installed"
}

ensure_namespace() {
    kubectl get ns "$NAMESPACE" >/dev/null 2>&1 || {
        log_info "Creating namespace $NAMESPACE..."
        kubectl create ns "$NAMESPACE"
    }
}

# ---------------------------------------------------------------------------
# Vault / secrets helpers
# ---------------------------------------------------------------------------

_is_vault_encrypted() {
    # shellcheck disable=SC2016
    head -1 "$1" 2>/dev/null | grep -q '^\$ANSIBLE_VAULT;'
}

_require_vault_pass() {
    [[ -f "$VAULT_PASS_FILE" ]] || log_err \
        "Vault password file not found: $VAULT_PASS_FILE" \
        "Create: echo 'your-password' > $VAULT_PASS_FILE && chmod 600 $VAULT_PASS_FILE"
}

_source_secrets() {
    [[ -f "$SECRETS_FILE" ]] || log_err \
        "Secrets file not found: $SECRETS_FILE" \
        "Run: cp ${SCRIPT_DIR}/secrets.template.env $SECRETS_FILE && edit it"

    if _is_vault_encrypted "$SECRETS_FILE"; then
        _require_vault_pass
        local tmp
        tmp=$(mktemp)
        # shellcheck disable=SC2064
        trap "rm -f '$tmp'" RETURN
        ansible-vault decrypt "$SECRETS_FILE" --vault-password-file "$VAULT_PASS_FILE" --output "$tmp"
        # shellcheck source=/dev/null
        source "$tmp"
    else
        # shellcheck source=/dev/null
        source "$SECRETS_FILE"
    fi
}

_ensure_secret() {
    local secret_name="$1" key="$2" value="$3"
    [[ -n "$value" ]] || return 0
    kubectl -n "$NAMESPACE" delete secret "$secret_name" 2>/dev/null || true
    kubectl -n "$NAMESPACE" create secret generic "$secret_name" --from-literal="$key=$value"
    log_ok "Secret $secret_name created"
}

# ---------------------------------------------------------------------------
# Commands: Operator lifecycle
# ---------------------------------------------------------------------------

cmd_install() {
    ensure_helm

    log_info "Installing OpenClaw Operator..."
    helm install "$OPERATOR_RELEASE" "$OPERATOR_CHART" \
        --namespace "$OPERATOR_NS" \
        --create-namespace

    log_info "Waiting for Operator pod..."
    kubectl -n "$OPERATOR_NS" wait --for=condition=ready pod -l app.kubernetes.io/name=openclaw-operator --timeout=120s 2>/dev/null || {
        log_warn "Operator pod not ready yet, check: kubectl get pods -n $OPERATOR_NS"
    }

    log_info "Verifying CRD..."
    if kubectl get crd openclawinstances.openclaw.rocks >/dev/null 2>&1; then
        log_ok "CRD openclawinstances.openclaw.rocks registered"
    else
        log_warn "CRD not found yet, it may take a moment"
    fi

    echo ""
    log_info "Next steps:"
    echo "  1. Create secrets:  $0 setup-secrets"
    echo "  2. Deploy agent:    $0 create <agent-name>"
    echo ""
    log_ok "OpenClaw Operator installed"
}

cmd_upgrade() {
    ensure_helm
    if ! helm -n "$OPERATOR_NS" status "$OPERATOR_RELEASE" >/dev/null 2>&1; then
        log_err "Helm release '$OPERATOR_RELEASE' not found in namespace $OPERATOR_NS" \
            "Run: $0 install"
    fi
    log_info "Upgrading OpenClaw Operator..."
    helm upgrade "$OPERATOR_RELEASE" "$OPERATOR_CHART" \
        --namespace "$OPERATOR_NS" \
        --reuse-values
    log_info "Waiting for Operator rollout..."
    kubectl -n "$OPERATOR_NS" rollout status deploy/openclaw-operator --timeout=120s 2>/dev/null || {
        log_warn "Operator rollout not confirmed; check: kubectl get pods -n $OPERATOR_NS"
    }
    log_ok "Operator upgraded"
}

cmd_uninstall() {
    log_warn "This will remove ALL OpenClaw agents, secrets, PVCs, and the Operator!"
    read -rp "Continue? [y/N] " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

    log_info "Deleting all agent instances..."
    kubectl -n "$NAMESPACE" delete openclawinstances --all --timeout=120s 2>/dev/null || true

    log_info "Waiting for agent pods to terminate..."
    kubectl -n "$NAMESPACE" wait --for=delete pod -l app.kubernetes.io/name=openclaw --timeout=120s 2>/dev/null || true

    log_info "Deleting remaining resources in $NAMESPACE..."
    kubectl -n "$NAMESPACE" delete statefulsets,services,configmaps,secrets,pvc,networkpolicies,servicemonitors \
        -l app.kubernetes.io/managed-by=openclaw-operator --timeout=60s 2>/dev/null || true

    log_info "Uninstalling Operator (Helm)..."
    helm -n "$OPERATOR_NS" uninstall "$OPERATOR_RELEASE" --wait 2>/dev/null || true

    log_info "Deleting namespaces..."
    kubectl delete ns "$NAMESPACE" --ignore-not-found --timeout=120s 2>/dev/null || true
    kubectl delete ns "$OPERATOR_NS" --ignore-not-found --timeout=120s 2>/dev/null || true

    log_info "Cleaning up CRD..."
    kubectl delete crd openclawinstances.openclaw.rocks 2>/dev/null || true

    log_ok "OpenClaw fully uninstalled"
}

cmd_apply_infra() {
    ensure_namespace
    log_info "Applying OpenClaw cluster manifests (monitoring rules, Longhorn jobs, quotas)..."
    kubectl apply -f "${CONFIG_DIR}/prometheus-rules.yaml"
    kubectl apply -f "${CONFIG_DIR}/longhorn-backup.yaml"
    kubectl apply -f "${CONFIG_DIR}/namespace-policies.yaml"
    log_ok "Infra manifests applied"
    echo "  Longhorn backup RecurringJob requires a configured backup target or backup tasks will fail."
}

# ---------------------------------------------------------------------------
# Commands: Secrets management
# ---------------------------------------------------------------------------

cmd_setup_secrets() {
    ensure_namespace
    _source_secrets

    log_info "Creating/updating openclaw-api-keys secret..."
    local api_args=()
    [[ -n "${SKYAPI_API_KEY:-}" ]]     && api_args+=(--from-literal=SKYAPI_API_KEY="$SKYAPI_API_KEY")
    [[ -n "${ALIYUN_API_KEY:-}" ]]     && api_args+=(--from-literal=ALIYUN_API_KEY="$ALIYUN_API_KEY")
    [[ -n "${ANTHROPIC_API_KEY:-}" ]]  && api_args+=(--from-literal=ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY")
    [[ -n "${OPENROUTER_API_KEY:-}" ]] && api_args+=(--from-literal=OPENROUTER_API_KEY="$OPENROUTER_API_KEY")

    if [[ ${#api_args[@]} -eq 0 ]]; then
        log_err "No API keys configured in $SECRETS_FILE"
    fi

    kubectl -n "$NAMESPACE" delete secret openclaw-api-keys 2>/dev/null || true
    kubectl -n "$NAMESPACE" create secret generic openclaw-api-keys "${api_args[@]}"
    log_ok "Secret openclaw-api-keys created"

    kubectl -n "$NAMESPACE" delete secret openclaw-channel-keys 2>/dev/null || true
    kubectl -n "$NAMESPACE" create secret generic openclaw-channel-keys \
        --from-literal=TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
    log_ok "Secret openclaw-channel-keys updated (TELEGRAM_BOT_TOKEN optional)"

    _ensure_secret openclaw-mem0-keys       MEM0_API_KEY        "${MEM0_API_KEY:-}"
    _ensure_secret openclaw-supermemory-keys SUPERMEMORY_API_KEY "${SUPERMEMORY_API_KEY:-}"
    _ensure_secret tailscale-authkey         authkey             "${TAILSCALE_AUTHKEY:-}"

    log_ok "Secrets configured"
}

cmd_encrypt_secrets() {
    _require_vault_pass
    [[ -f "$SECRETS_FILE" ]] || log_err "Secrets file not found: $SECRETS_FILE"
    if _is_vault_encrypted "$SECRETS_FILE"; then
        log_info "$SECRETS_FILE is already encrypted, skipping"
        return 0
    fi
    ansible-vault encrypt "$SECRETS_FILE" --vault-password-file "$VAULT_PASS_FILE"
    log_ok "Encrypted $SECRETS_FILE in-place (safe to commit)"
}

cmd_decrypt_secrets() {
    _require_vault_pass
    [[ -f "$SECRETS_FILE" ]] || log_err "Secrets file not found: $SECRETS_FILE"
    if ! _is_vault_encrypted "$SECRETS_FILE"; then
        log_info "$SECRETS_FILE is already decrypted, skipping"
        return 0
    fi
    ansible-vault decrypt "$SECRETS_FILE" --vault-password-file "$VAULT_PASS_FILE"
    log_ok "Decrypted $SECRETS_FILE in-place"
}

cmd_test_secrets() {
    _source_secrets

    local has_error=false

    _judge_response() {
        local label="$1" http_code="$2" body="$3" model="$4"
        case "$http_code" in
            200) log_ok "$label OK (200)"; return 0 ;;
            429) log_ok "$label OK (rate-limited, key valid)"; return 0 ;;
            400)
                if echo "$body" | grep -q "not supported"; then
                    log_warn "$label reachable, but model '$model' not supported"
                else
                    log_ok "$label reachable (400: $(echo "$body" | grep -o '"message":"[^"]*"' | head -1))"
                    return 0
                fi ;;
            401|403) log_warn "$label FAILED (${http_code}: invalid API key)" ;;
            *) log_warn "$label FAILED (HTTP $http_code)"; echo "  Response: $body" ;;
        esac
        return 1
    }

    _test_one_api() {
        local label="$1" url="$2" model="$3"
        shift 3
        log_info "Testing $label -> $url (model: $model) ..."
        local raw http_code body
        raw=$(curl -s --max-time 15 -w '\n%{http_code}' \
            -H "content-type: application/json" \
            -d "{\"model\":\"$model\",\"max_tokens\":1,\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}" \
            "$@" "$url" 2>&1)
        http_code=$(echo "$raw" | tail -1)
        body=$(echo "$raw" | sed '$d')
        _judge_response "$label" "$http_code" "$body" "$model" || has_error=true
    }

    if [[ -n "${SKYAPI_API_KEY:-}" ]]; then
        _test_one_api "SkyAPI" "${SKYAPI_BASE_URL:-https://api.skyapi.org}/v1/messages" "claude-sonnet-4-5" \
            -H "x-api-key: $SKYAPI_API_KEY" \
            -H "anthropic-version: 2023-06-01"
    fi

    if [[ -n "${ALIYUN_API_KEY:-}" ]]; then
        _test_one_api "Aliyun" "${ALIYUN_BASE_URL:-https://coding.dashscope.aliyuncs.com/v1}/chat/completions" "qwen3-coder-plus" \
            -H "Authorization: Bearer $ALIYUN_API_KEY"
    fi

    if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
        _test_one_api "Anthropic" "${ANTHROPIC_BASE_URL:-https://api.anthropic.com}/v1/messages" "claude-sonnet-4-20250514" \
            -H "x-api-key: $ANTHROPIC_API_KEY" \
            -H "anthropic-version: 2023-06-01"
    fi

    if [[ -z "${SKYAPI_API_KEY:-}${ALIYUN_API_KEY:-}${ANTHROPIC_API_KEY:-}" ]]; then
        log_err "No platform API keys configured in $SECRETS_FILE"
    fi

    echo ""
    if $has_error; then
        log_warn "Some API tests failed. Fix the keys/URLs in $SECRETS_FILE and retry."
        return 1
    fi
    log_ok "All API tests passed. Run: $0 setup-secrets"
}

cmd_test_connectivity() {
    exec bash "${SCRIPT_DIR}/test-connectivity.sh" "$@"
}

# ---------------------------------------------------------------------------
# Ingress helpers
# ---------------------------------------------------------------------------

_apply_ingress() {
    local name="$1"
    local host="${name}.${INGRESS_DOMAIN}"
    log_info "Applying Ingress ${name}-ingress -> ${host} ..."
    kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${name}-ingress
  namespace: ${NAMESPACE}
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/limit-rps: "30"
    nginx.ingress.kubernetes.io/proxy-connect-timeout: "30"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-http-version: "1.1"
    nginx.ingress.kubernetes.io/websocket-services: "${name}"
    nginx.ingress.kubernetes.io/proxy-buffering: "off"
    nginx.ingress.kubernetes.io/proxy-request-buffering: "off"
spec:
  ingressClassName: nginx
  rules:
    - host: ${host}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: ${name}
                port:
                  number: 18789
EOF
    log_ok "Ingress: https://${host}"
}

_delete_ingress() {
    local name="$1"
    kubectl -n "$NAMESPACE" delete ingress "${name}-ingress" 2>/dev/null && \
        log_ok "Ingress ${name}-ingress deleted" || true
}

# ---------------------------------------------------------------------------
# Commands: Agent CRUD
# ---------------------------------------------------------------------------

cmd_create() {
    local name="${1:-}"
    [[ -n "$name" ]] || log_err "Usage: $0 create <agent-name>"

    ensure_namespace

    if ! kubectl -n "$NAMESPACE" get secret openclaw-api-keys >/dev/null 2>&1; then
        log_err "Secret 'openclaw-api-keys' not found in namespace $NAMESPACE" \
                "Run first: $0 setup-secrets"
    fi

    local yaml_file="${CONFIG_DIR}/${name}.yaml"

    if [[ -f "$yaml_file" ]]; then
        log_info "Applying existing $yaml_file..."
    else
        log_info "Generating $yaml_file from template..."
        # Agent names must be DNS-safe (lowercase alphanumeric + hyphens)
        sed "s/AGENT_NAME/${name}/g" "${CONFIG_DIR}/agent-template.yaml" > "$yaml_file"
    fi

    kubectl apply -f "$yaml_file"
    log_info "Waiting for agent to become ready..."
    kubectl -n "$NAMESPACE" wait --for=jsonpath='{.status.phase}'=Running openclawinstance/"$name" --timeout=120s 2>/dev/null || {
        log_warn "Agent not ready yet. Check: kubectl get openclawinstances -n $NAMESPACE"
    }

    _apply_ingress "$name"

    log_ok "Agent '$name' deployed"
    echo ""
    echo "  Web UI:       https://${name}.${INGRESS_DOMAIN}"
    echo "  Port-forward: kubectl port-forward -n $NAMESPACE svc/$name 18789:18789"
    echo "  Logs:         kubectl logs -n $NAMESPACE statefulset/$name -f"
}

cmd_delete() {
    local name="${1:-}"
    [[ -n "$name" ]] || log_err "Usage: $0 delete <agent-name>"

    log_info "Deleting agent '$name' (Operator will auto-backup if configured)..."
    kubectl -n "$NAMESPACE" delete openclawinstance "$name" --timeout=120s 2>/dev/null || {
        log_warn "Agent '$name' not found or already deleted"
    }

    _delete_ingress "$name"

    log_ok "Agent '$name' deleted"
}

# ---------------------------------------------------------------------------
# Commands: Diagnostics
# ---------------------------------------------------------------------------

cmd_list() {
    echo "=== OpenClaw Agent Instances ==="
    kubectl -n "$NAMESPACE" get openclawinstances -o wide 2>/dev/null || echo "(none found)"
}

cmd_status() {
    echo "=== Operator ==="
    kubectl -n "$OPERATOR_NS" get pods -o wide 2>/dev/null || echo "(not installed)"
    echo ""
    echo "=== Agent Instances ==="
    kubectl -n "$NAMESPACE" get openclawinstances -o wide 2>/dev/null || echo "(none)"
    echo ""
    echo "=== Pods ==="
    kubectl -n "$NAMESPACE" get pods -o wide 2>/dev/null || echo "(none)"
    echo ""
    echo "=== PVCs ==="
    kubectl -n "$NAMESPACE" get pvc 2>/dev/null || echo "(none)"
    echo ""
    echo "=== Secrets ==="
    kubectl -n "$NAMESPACE" get secrets --no-headers 2>/dev/null | awk '{print $1}' || echo "(none)"
}

cmd_logs() {
    local name="${1:-}"
    [[ -n "$name" ]] || log_err "Usage: $0 logs <agent-name>"
    kubectl -n "$NAMESPACE" logs "statefulset/$name" -f --all-containers
}

cmd_forward() {
    local name="${1:-}"
    local port="${2:-18789}"
    [[ -n "$name" ]] || log_err "Usage: $0 forward <agent-name> [local-port]"
    log_info "Forwarding localhost:$port -> $name:18789 ..."
    kubectl -n "$NAMESPACE" port-forward "svc/$name" "${port}:18789"
}

cmd_check() {
    local pass=0 fail=0
    _ok()   { log_ok "$1"; ((pass++)) || true; }
    _fail() { log_warn "$1"; ((fail++)) || true; }

    echo "=== Infrastructure Check ==="
    echo ""

    # Operator
    if kubectl -n "$OPERATOR_NS" get deploy openclaw-operator >/dev/null 2>&1; then
        local ready
        ready=$(kubectl -n "$OPERATOR_NS" get deploy openclaw-operator -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
        if [[ "${ready:-0}" -ge 1 ]]; then _ok "Operator: Running"; else _fail "Operator: Not ready"; fi
    else
        _fail "Operator: Not installed"
    fi

    # CRD
    if kubectl get crd openclawinstances.openclaw.rocks >/dev/null 2>&1; then
        _ok "CRD: openclawinstances registered"
    else
        _fail "CRD: openclawinstances not found"
    fi

    # Namespace
    if kubectl get ns "$NAMESPACE" >/dev/null 2>&1; then
        _ok "Namespace: $NAMESPACE exists"
    else
        _fail "Namespace: $NAMESPACE not found"
    fi

    # Secrets
    if kubectl -n "$NAMESPACE" get secret openclaw-api-keys >/dev/null 2>&1; then
        _ok "Secret: openclaw-api-keys"
    else
        _fail "Secret: openclaw-api-keys missing (run: $0 setup-secrets)"
    fi

    # Agent instances
    local agents
    agents=$(kubectl -n "$NAMESPACE" get openclawinstances --no-headers 2>/dev/null | wc -l)
    if [[ "$agents" -gt 0 ]]; then
        _ok "Agents: $agents instance(s) deployed"
        kubectl -n "$NAMESPACE" get openclawinstances --no-headers 2>/dev/null | while read -r name phase ready _rest; do
            if [[ "$phase" == "Running" && "$ready" == "True" ]]; then
                log_ok "  $name: $phase (ready)"
            else
                log_warn "  $name: $phase (ready=$ready)"
            fi
        done
    else
        _fail "Agents: none deployed"
    fi

    # Pod health
    local unhealthy
    unhealthy=$(kubectl -n "$NAMESPACE" get pods --no-headers 2>/dev/null | grep -c -v -E 'Running|Completed' || true)
    if [[ "$unhealthy" -eq 0 ]]; then _ok "Pods: all healthy"; else _fail "Pods: $unhealthy unhealthy"; fi

    # Ingress (per agent)
    local agent_names
    agent_names=$(kubectl -n "$NAMESPACE" get openclawinstances --no-headers 2>/dev/null | awk '{print $1}')
    for a in $agent_names; do
        if kubectl -n "$NAMESPACE" get ingress "${a}-ingress" >/dev/null 2>&1; then
            local ing_host
            ing_host=$(kubectl -n "$NAMESPACE" get ingress "${a}-ingress" -o jsonpath='{.spec.rules[0].host}' 2>/dev/null)
            _ok "Ingress: ${a} -> ${ing_host}"
        else
            _fail "Ingress: ${a}-ingress missing (redeploy: $0 create $a)"
        fi
    done

    # NetworkPolicy (optional)
    local np_count
    np_count=$(kubectl -n "$NAMESPACE" get networkpolicies --no-headers 2>/dev/null | wc -l)
    if [[ "$np_count" -gt 0 ]]; then
        _ok "NetworkPolicy: $np_count rule(s)"
    else
        log_info "NetworkPolicy: none (optional)"
    fi

    # PrometheusRule (optional)
    if kubectl -n "$NAMESPACE" get prometheusrule openclaw-alerts >/dev/null 2>&1; then
        _ok "PrometheusRule: openclaw-alerts"
    else
        log_info "PrometheusRule: not configured (optional)"
    fi

    if kubectl -n "$NAMESPACE" get resourcequota openclaw-quota >/dev/null 2>&1; then
        _ok "ResourceQuota: openclaw-quota"
    else
        log_info "ResourceQuota: openclaw-quota missing (run: $0 apply-infra)"
    fi

    # ServiceMonitor (optional)
    local sm_count
    sm_count=$(kubectl -n "$NAMESPACE" get servicemonitor --no-headers 2>/dev/null | wc -l)
    if [[ "$sm_count" -gt 0 ]]; then
        _ok "ServiceMonitor: $sm_count configured"
    else
        log_info "ServiceMonitor: none (optional)"
    fi

    # Longhorn PVCs
    local pvc_count
    pvc_count=$(kubectl -n "$NAMESPACE" get pvc --no-headers 2>/dev/null | wc -l)
    if [[ "$pvc_count" -gt 0 ]]; then
        _ok "PVCs: $pvc_count bound"
    else
        _fail "PVCs: none"
    fi

    echo ""
    echo "=== Result: $pass passed, $fail failed ==="
    [[ "$fail" -eq 0 ]] || return 1
}

cmd_diagnose() {
    echo "=== Operator Pod ==="
    kubectl -n "$OPERATOR_NS" get pods -o wide 2>/dev/null || echo "(not found)"
    echo ""
    echo "=== Operator Logs (last 50 lines) ==="
    kubectl -n "$OPERATOR_NS" logs deploy/openclaw-operator --tail=50 2>/dev/null || echo "(no logs)"
    echo ""
    echo "=== Agent Instances ==="
    kubectl -n "$NAMESPACE" get openclawinstances -o wide 2>/dev/null || echo "(none)"
    echo ""
    echo "=== Pods ==="
    kubectl -n "$NAMESPACE" get pods -o wide 2>/dev/null || echo "(none)"
    echo ""
    echo "=== Agent Events (last 20) ==="
    kubectl -n "$NAMESPACE" get events --sort-by='.lastTimestamp' 2>/dev/null | tail -20 || echo "(none)"
    echo ""
    echo "=== Secrets ==="
    kubectl -n "$NAMESPACE" get secrets --no-headers 2>/dev/null | awk '{print $1}' || echo "(none)"
    echo ""
    echo "=== NetworkPolicies ==="
    kubectl -n "$NAMESPACE" get networkpolicies 2>/dev/null || echo "(none)"
    echo ""
    echo "=== Ingress ==="
    kubectl -n "$NAMESPACE" get ingress -o wide 2>/dev/null || echo "(none)"
    echo ""
    echo "=== ServiceMonitors ==="
    kubectl -n "$NAMESPACE" get servicemonitor 2>/dev/null || echo "(none)"
}

cmd_token() {
    local name="${1:-}"
    [[ -n "$name" ]] || log_err "Usage: $0 token <agent-name>"

    local secret_name="${name}-gateway-token"
    local token
    token=$(kubectl -n "$NAMESPACE" get secret "$secret_name" -o jsonpath='{.data.token}' 2>/dev/null) || {
        log_err "Secret '$secret_name' not found. Is agent '$name' deployed?"
    }

    echo "$token" | base64 -d
    echo ""
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

case "${1:-}" in
    install)          cmd_install ;;
    upgrade)          cmd_upgrade ;;
    uninstall)        cmd_uninstall ;;
    apply-infra)      cmd_apply_infra ;;
    setup-secrets)    cmd_setup_secrets ;;
    encrypt-secrets)  cmd_encrypt_secrets ;;
    decrypt-secrets)  cmd_decrypt_secrets ;;
    test-secrets)     cmd_test_secrets ;;
    test-connectivity) cmd_test_connectivity "${@:2}" ;;
    create)           cmd_create "${2:-}" ;;
    delete)           cmd_delete "${2:-}" ;;
    list)             cmd_list ;;
    status)           cmd_status ;;
    check)            cmd_check ;;
    logs)             cmd_logs "${2:-}" ;;
    forward)          cmd_forward "${2:-}" "${3:-}" ;;
    token)            cmd_token "${2:-}" ;;
    diagnose)         cmd_diagnose ;;
    *)
        cat <<EOF
Usage: $0 <command> [args]

Commands:
  install            Install OpenClaw Operator (Helm chart)
  upgrade            Upgrade Operator in-place (helm upgrade --reuse-values)
  uninstall          Remove all Agents and Operator
  apply-infra        Apply prometheus-rules, longhorn-backup, namespace ResourceQuota
  setup-secrets      Create/update Kubernetes secrets from secrets.env
  encrypt-secrets    Encrypt secrets.env in-place (safe to commit)
  decrypt-secrets    Decrypt secrets.env in-place (for editing)
  test-secrets       Test LLM API keys from secrets.env
  test-connectivity [opts]  Test Telegram (getMe) and S3 (aws s3 ls); --send-telegram | --skip-telegram
  create <name>      Deploy Agent + Ingress (<name>.${INGRESS_DOMAIN})
  delete <name>      Delete Agent + Ingress (auto-backup if configured)
  list               List all Agent instances
  status             Show Operator and Agent status
  check              Verify all infrastructure components are deployed
  logs <name>        Stream agent logs
  forward <name>     Port-forward agent UI to localhost:18789
  token <name>       Show gateway token for an Agent instance
  diagnose           Debug connectivity and events
EOF
        exit 1
        ;;
esac
