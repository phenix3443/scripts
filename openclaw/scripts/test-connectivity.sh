#!/usr/bin/env bash
#
# test-connectivity.sh - Verify TELEGRAM_* and S3_* from secrets.env
#
# Usage:
#   ./test-connectivity.sh                  # Telegram getMe + S3 list (no chat message)
#   ./test-connectivity.sh --send-telegram # Also send a test message to TELEGRAM_CHAT_ID
#   ./test-connectivity.sh --skip-telegram # Only S3 (e.g. TLS/proxy issues to api.telegram.org)
#
# Requires: curl; optional: aws (install: make install-deps)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_FILE="${SCRIPT_DIR}/secrets.env"
VAULT_PASS_FILE="${SCRIPT_DIR}/../../ansible/.vault_pass"

SEND_TELEGRAM=false
SKIP_TELEGRAM=false
for a in "$@"; do
    case "$a" in
        --send-telegram) SEND_TELEGRAM=true ;;
        --skip-telegram) SKIP_TELEGRAM=true ;;
    esac
done

log_info() { echo "[INFO] $*"; }
log_ok()   { echo "[OK]   $*"; }
log_warn() { echo "[WARN] $*" >&2; }
log_err()  { echo "[ERR]  $*" >&2; }

_source_secrets() {
    [[ -f "$SECRETS_FILE" ]] || { log_err "Missing $SECRETS_FILE"; exit 1; }
    if head -1 "$SECRETS_FILE" 2>/dev/null | grep -q '^\$ANSIBLE_VAULT;'; then
        [[ -f "$VAULT_PASS_FILE" ]] || { log_err "Vault password not found: $VAULT_PASS_FILE"; exit 1; }
        local tmp
        tmp=$(mktemp)
        trap 'rm -f "$tmp"' EXIT
        ansible-vault decrypt "$SECRETS_FILE" --vault-password-file "$VAULT_PASS_FILE" --output "$tmp"
        # shellcheck source=/dev/null
        source "$tmp"
    else
        # shellcheck source=/dev/null
        source "$SECRETS_FILE"
    fi
}

_test_telegram() {
    echo ""
    echo "=== Telegram ==="
    if [[ "$SKIP_TELEGRAM" == true ]]; then
        log_info "Skipped (--skip-telegram)"
        return 0
    fi
    if [[ -z "${TELEGRAM_BOT_TOKEN:-}" ]]; then
        log_warn "TELEGRAM_BOT_TOKEN not set; skip"
        return 0
    fi
    local url="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe"
    local body
    body=$(curl -fsS --max-time 15 "$url" 2>&1) || {
        log_err "getMe failed: $body"
        if echo "$body" | grep -qiE 'SSL|certificate|TLS'; then
            log_warn "TLS/certificate error: disable HTTPS MITM proxy for api.telegram.org, or trust your corporate CA (export SSL_CERT_FILE=...)."
        fi
        return 1
    }
    if echo "$body" | grep -q '"ok":true'; then
        log_ok "getMe OK (bot token is valid)"
    else
        log_err "getMe returned not ok: $body"
        return 1
    fi
    if [[ "$SEND_TELEGRAM" != true ]]; then
        log_info "Skip sendMessage (use --send-telegram to post a test message)"
        return 0
    fi
    if [[ -z "${TELEGRAM_CHAT_ID:-}" ]]; then
        log_warn "TELEGRAM_CHAT_ID not set; cannot send test message"
        return 0
    fi
    url="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage"
    body=$(curl -fsS --max-time 15 -X POST "$url" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        --data-urlencode "text=OpenClaw connectivity test $(date -u +%Y-%m-%dT%H:%M:%SZ)" 2>&1) || {
        log_err "sendMessage failed: $body"
        return 1
    }
    if echo "$body" | grep -q '"ok":true'; then
        log_ok "sendMessage OK (check your Telegram chat)"
    else
        log_err "sendMessage not ok: $body"
        return 1
    fi
}

_s3_fully_configured() {
    [[ -n "${S3_ACCESS_KEY_ID:-}" && -n "${S3_SECRET_ACCESS_KEY:-}" && \
       -n "${S3_ENDPOINT:-}" && -n "${S3_BUCKET:-}" ]]
}

_validate_s3_env() {
    if [[ ! "$S3_ENDPOINT" =~ ^https:// ]]; then
        log_err "S3_ENDPOINT must be an HTTPS URL, e.g. https://<account-id>.r2.cloudflarestorage.com"
        log_err "It must not be the same value as S3_SECRET_ACCESS_KEY."
        return 1
    fi
    return 0
}

_test_s3_aws() {
    echo ""
    echo "=== S3-compatible (aws cli) ==="
    if ! command -v aws >/dev/null 2>&1; then
        log_warn "aws CLI not found; install awscli to verify S3 (brew install awscli)"
        return 0
    fi
    export AWS_ACCESS_KEY_ID="$S3_ACCESS_KEY_ID"
    export AWS_SECRET_ACCESS_KEY="$S3_SECRET_ACCESS_KEY"
    local region="${S3_REGION:-auto}"
    if [[ "$region" == "auto" ]]; then
        region="us-east-1"
    fi
    if aws s3 ls "s3://${S3_BUCKET}/" --endpoint-url "$S3_ENDPOINT" --region "$region" 2>&1; then
        log_ok "aws s3 ls s3://${S3_BUCKET}/ OK"
    else
        log_err "aws s3 ls failed (check keys, endpoint URL, bucket name, region; R2 uses endpoint like https://<id>.r2.cloudflarestorage.com)"
        return 1
    fi
}

main() {
    _source_secrets

    local failed=0

    echo "=== Format hints ==="
    if [[ -n "${TELEGRAM_BOT_TOKEN:-}" ]] && [[ ! "$TELEGRAM_BOT_TOKEN" =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]]; then
        log_warn "TELEGRAM_BOT_TOKEN format looks unusual (expected digits:alphanumeric token from BotFather)"
    fi

    _test_telegram || failed=1

    if ! _s3_fully_configured; then
        echo ""
        echo "=== S3 ==="
        log_warn "S3 not fully configured (need S3_ACCESS_KEY_ID, S3_SECRET_ACCESS_KEY, S3_ENDPOINT, S3_BUCKET); skip"
        echo ""
        if [[ "$failed" -ne 0 ]]; then
            log_err "Telegram check failed; fix TLS/proxy or use --skip-telegram to test S3 only."
            exit 1
        fi
        log_ok "Done (Telegram only or partial S3)"
        exit 0
    fi

    _validate_s3_env || exit 1
    log_ok "S3_ENDPOINT looks like a valid URL"

    _test_s3_aws || failed=1
    echo ""
    if [[ "$failed" -ne 0 ]]; then
        log_err "One or more checks failed (Telegram and/or S3)."
        exit 1
    fi
    log_ok "All connectivity checks passed"
}

main "$@"
