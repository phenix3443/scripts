#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORTAL_SCRIPT="${SCRIPT_DIR}/portal-auto-login.sh"
SERVICE_SRC="${SCRIPT_DIR}/portal.service.example"
TIMER_SRC="${SCRIPT_DIR}/portal.timer.example"
SERVICE_DEST="/etc/systemd/system/portal.service"
TIMER_DEST="/etc/systemd/system/portal.timer"

usage() {
  cat <<USAGE
Usage: $0 [install|uninstall|status]

Commands:
  install    Create and enable systemd timer (every 10 minutes)
  uninstall  Disable timer and remove unit files
  status     Show timer status
USAGE
}

install_timer() {
  if [[ ! -f "$PORTAL_SCRIPT" ]]; then
    echo "ERROR: portal-auto-login.sh not found: $PORTAL_SCRIPT" >&2
    exit 1
  fi
  if [[ ! -f "$SERVICE_SRC" || ! -f "$TIMER_SRC" ]]; then
    echo "ERROR: portal.service.example or portal.timer.example not found in $SCRIPT_DIR" >&2
    exit 1
  fi

  echo "Installing systemd timer for portal auto-login..."
  sed -e "s|@SCRIPT_PATH@|${PORTAL_SCRIPT}|g" -e "s|@SCRIPT_DIR@|${SCRIPT_DIR}|g" "$SERVICE_SRC" > "$SERVICE_DEST"
  cp "$TIMER_SRC" "$TIMER_DEST"

  systemctl daemon-reload
  systemctl enable portal.timer
  systemctl start portal.timer

  echo "Portal timer installed and started"
  echo "  Script: $PORTAL_SCRIPT"
  echo "  Check: systemctl status portal.timer"
  echo "  Logs:  journalctl -u portal.service"
}

uninstall_timer() {
  echo "Uninstalling portal timer..."
  systemctl stop portal.timer 2>/dev/null || true
  systemctl disable portal.timer 2>/dev/null || true
  rm -f "$SERVICE_DEST" "$TIMER_DEST"
  systemctl daemon-reload
  echo "Portal timer uninstalled"
}

show_status() {
  if [[ -f "$TIMER_DEST" ]]; then
    systemctl status portal.timer --no-pager
    echo ""
    echo "Recent runs:"
    journalctl -u portal.service -n 10 --no-pager
  else
    echo "Portal timer is not installed"
    exit 1
  fi
}

case "${1:-}" in
  install)
    [[ "$(id -u)" -ne 0 ]] && { echo "ERROR: Must run as root (e.g. sudo $0 install)"; exit 1; }
    install_timer
    ;;
  uninstall)
    [[ "$(id -u)" -ne 0 ]] && { echo "ERROR: Must run as root"; exit 1; }
    uninstall_timer
    ;;
  status)
    show_status
    ;;
  -h|--help)
    usage
    ;;
  *)
    usage
    exit 1
    ;;
esac
