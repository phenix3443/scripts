#!/usr/bin/env bash
#
# setup-backup-target.sh - Configure Longhorn S3 backup target
#
# Usage:
#   1. Fill in S3 credentials in secrets.env:
#      S3_ACCESS_KEY_ID=xxx
#      S3_SECRET_ACCESS_KEY=xxx
#      S3_ENDPOINT=https://xxx.r2.cloudflarestorage.com
#      S3_BUCKET=openclaw-backup
#      S3_REGION=auto
#
#   2. Run: ./setup-backup-target.sh
#
# Supports: Cloudflare R2, Backblaze B2, MinIO, AWS S3, Aliyun OSS

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_FILE="${SCRIPT_DIR}/secrets.env"
VAULT_PASS_FILE="${SCRIPT_DIR}/../../ansible/.vault_pass"

log_info()  { echo "[INFO] $*"; }
log_ok()    { echo "[OK]   $*"; }
log_err()   { echo "[ERR]  $*" >&2; exit 1; }

# Decrypt and source secrets
if [[ ! -f "$SECRETS_FILE" ]]; then
    log_err "Secrets file not found: $SECRETS_FILE"
fi

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

# Validate required variables
: "${S3_ACCESS_KEY_ID:?Missing S3_ACCESS_KEY_ID in secrets.env}"
: "${S3_SECRET_ACCESS_KEY:?Missing S3_SECRET_ACCESS_KEY in secrets.env}"
: "${S3_ENDPOINT:?Missing S3_ENDPOINT in secrets.env}"
: "${S3_BUCKET:?Missing S3_BUCKET in secrets.env}"
: "${S3_REGION:-auto}"

log_info "Configuring Longhorn backup target..."
log_info "  Endpoint: $S3_ENDPOINT"
log_info "  Bucket:   $S3_BUCKET"
log_info "  Region:   $S3_REGION"

# Create Kubernetes Secret for S3 credentials
kubectl -n longhorn-system delete secret longhorn-backup-s3 2>/dev/null || true
kubectl -n longhorn-system create secret generic longhorn-backup-s3 \
    --from-literal=AWS_ACCESS_KEY_ID="$S3_ACCESS_KEY_ID" \
    --from-literal=AWS_SECRET_ACCESS_KEY="$S3_SECRET_ACCESS_KEY" \
    --from-literal=AWS_ENDPOINTS="$S3_ENDPOINT"

log_ok "Secret longhorn-backup-s3 created"

# Configure backup target via Settings CRD
BACKUP_TARGET="s3://${S3_BUCKET}@${S3_REGION}/"

kubectl apply -f - <<EOF
apiVersion: longhorn.io/v1beta2
kind: Setting
metadata:
  name: backup-target
  namespace: longhorn-system
value: "${BACKUP_TARGET}"
---
apiVersion: longhorn.io/v1beta2
kind: Setting
metadata:
  name: backup-target-credential-secret
  namespace: longhorn-system
value: "longhorn-backup-s3"
EOF

log_ok "Longhorn backup target configured: $BACKUP_TARGET"

# Verify configuration
log_info "Verifying backup target..."
sleep 3
kubectl -n longhorn-system get setting backup-target -o jsonpath='{.value}' && echo ""
kubectl -n longhorn-system get setting backup-target-credential-secret -o jsonpath='{.value}' && echo ""

log_ok "Backup target setup complete!"
echo ""
echo "Next steps:"
echo "  1. Test backup: kubectl -n openclaw exec hanbao-0 -- touch /data/test-backup"
echo "  2. Trigger backup: kubectl -n longhorn-system create -f - <<EOF"
echo "     apiVersion: longhorn.io/v1beta2"
echo "     kind: Backup"
echo "     metadata:"
echo "       name: test-backup"
echo "       namespace: longhorn-system"
echo "     spec:"
echo "       snapshotName: <snapshot-name>"
echo "     EOF"
echo "  3. Check Longhorn UI: Backup tab"
