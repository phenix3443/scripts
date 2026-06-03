#!/usr/bin/env bash
#
# setup-grafana-dashboard.sh - Auto-import OpenClaw Grafana dashboard
#
# Prerequisites:
#   - Grafana installed in cluster (kube-prometheus-stack or standalone)
#   - kubectl access to Grafana namespace
#
# Usage:
#   ./setup-grafana-dashboard.sh [grafana-namespace]
#
# Default grafana-namespace: monitoring

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DASHBOARD_FILE="${SCRIPT_DIR}/../config/grafana/openclaw-overview.json"
GRAFANA_NS="${1:-monitoring}"

log_info()  { echo "[INFO] $*"; }
log_ok()    { echo "[OK]   $*"; }
log_err()   { echo "[ERR]  $*" >&2; exit 1; }

[[ -f "$DASHBOARD_FILE" ]] || log_err "Dashboard file not found: $DASHBOARD_FILE"

log_info "Importing OpenClaw dashboard to Grafana in namespace: $GRAFANA_NS"

# Check if Grafana is using sidecar provisioning (common in kube-prometheus-stack)
if kubectl -n "$GRAFANA_NS" get deploy -l app.kubernetes.io/name=grafana >/dev/null 2>&1; then
    log_info "Detected Grafana deployment, using ConfigMap provisioning..."
    
    # Create ConfigMap with dashboard JSON
    kubectl -n "$GRAFANA_NS" create configmap openclaw-dashboard \
        --from-file=openclaw-overview.json="$DASHBOARD_FILE" \
        --dry-run=client -o yaml | \
    kubectl apply -f -
    
    # Add label for Grafana sidecar to discover it
    kubectl -n "$GRAFANA_NS" label configmap openclaw-dashboard \
        grafana_dashboard=1 \
        --overwrite
    
    log_ok "Dashboard ConfigMap created with label grafana_dashboard=1"
    log_info "Grafana sidecar will auto-import within 30s"
else
    log_info "Grafana not found in $GRAFANA_NS, trying API import..."
    
    # Fallback: direct API import (requires port-forward or Ingress)
    GRAFANA_URL="${GRAFANA_URL:-http://localhost:3000}"
    GRAFANA_USER="${GRAFANA_USER:-admin}"
    GRAFANA_PASS="${GRAFANA_PASS:-prom-operator}"
    
    log_info "Using Grafana API: $GRAFANA_URL"
    log_info "Credentials: $GRAFANA_USER / *** (set GRAFANA_PASS if different)"
    
    # Wrap dashboard JSON in API payload
    PAYLOAD=$(jq -n --slurpfile dashboard "$DASHBOARD_FILE" '{
        dashboard: $dashboard[0],
        overwrite: true,
        inputs: [],
        folderId: 0
    }')
    
    curl -X POST "$GRAFANA_URL/api/dashboards/db" \
        -H "Content-Type: application/json" \
        -u "$GRAFANA_USER:$GRAFANA_PASS" \
        -d "$PAYLOAD" \
        --fail --silent --show-error | jq .
    
    log_ok "Dashboard imported via API"
fi

echo ""
log_ok "OpenClaw dashboard setup complete!"
echo "  Access: Grafana UI → Dashboards → OpenClaw Overview"
echo "  UID: openclaw-overview"
