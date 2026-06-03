#!/bin/bash

# Setup script for Mac Mini (Intel) — run ON the mini itself
# Usage: ssh -t mini 'bash -s' < macos/setup-mini.sh

set -euo pipefail

KICKSTART="/System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart"
GOST_PLIST="$HOME/Library/LaunchAgents/com.gost.socks5.plist"
GOST_LABEL="com.gost.socks5"
GOST_PORT=1090

log()  { printf "\n[%s] %s\n" "$1" "$2"; }
info() { printf "  %s\n" "$1"; }
ok()   { printf "  ✓ %s\n" "$1"; }
warn() { printf "  ✗ %s\n" "$1"; }

echo "=== Mac Mini Setup ==="

log "1/3" "Screen Sharing (VNC)"
if sudo "$KICKSTART" -activate -configure -access -on -privs -all -restart -agent -menu >/dev/null 2>&1; then
    ok "enabled"
else
    warn "failed — check System Settings > General > Sharing manually"
fi

log "2/3" "Power Management"
sudo pmset -a sleep 0 disksleep 0 autorestart 1
ok "sleep=0  disksleep=0  autorestart=1"

log "3/3" "gost SOCKS5 Proxy (:${GOST_PORT})"
if launchctl list "$GOST_LABEL" >/dev/null 2>&1; then
    ok "launchd service loaded"
else
    warn "launchd service not loaded"
    if [ -f "$GOST_PLIST" ]; then
        launchctl load "$GOST_PLIST"
        ok "loaded $GOST_PLIST"
    else
        warn "$GOST_PLIST not found — install gost first"
    fi
fi

if lsof -i ":${GOST_PORT}" -sTCP:LISTEN >/dev/null 2>&1; then
    ok "listening on :${GOST_PORT}"
else
    warn "not listening on :${GOST_PORT}"
fi

ts_ip=$(tailscale ip -4 2>/dev/null || true)
lan_ip=$(ipconfig getifaddr en0 2>/dev/null || true)

echo ""
echo "=== Summary ==="
info "Tailscale : ${ts_ip:-unknown}"
info "LAN       : ${lan_ip:-unknown}"
[ -n "$ts_ip" ] && info "VNC       : vnc://${ts_ip}"
