#!/bin/bash
#
# sing-box.sh - sing-box service management script
#
# Description:
#   Comprehensive management script for sing-box proxy service.
#   Handles installation, configuration, service lifecycle, and system optimization.
#   Designed for Ubuntu/Debian systems with systemd.
#
# Usage:
#   sudo ./sing-box.sh <command>
#
# Commands:
#   install           Install sing-box binary and setup service
#   start             Start sing-box service
#   stop              Stop sing-box service
#   restart           Restart sing-box service
#   status            Show service status and listening ports
#   update-singbox    Update sing-box to latest version
#   update-config     Update configuration (via Ansible)
#   optimize-system   Optimize system parameters (BBR, TCP buffers)
#   uninstall         Uninstall sing-box (preserves config)
#   help              Show help message
#
# Environment Variables:
#   SINGBOX_VERSION   sing-box version to install (default: latest)
#   INSTALL_DIR       Binary installation directory (default: /usr/local/bin)
#   CONFIG_DIR        Configuration directory (default: /etc/sing-box)
#   SERVICE_USER      Service user (default: root)
#
# Dependencies:
#   - curl: download installation script
#   - systemd: service management
#   - jq: JSON processing (optional, for port detection)
#
# Notes:
#   - Requires root privileges for most operations
#   - Configuration should be deployed via Ansible
#   - Firewall (ufw) is configured automatically if available
#
# Author: home-lab project
# Repository: https://github.com/womenlia/home-lab
#

set -e
set -o pipefail

SINGBOX_VERSION="${SINGBOX_VERSION:-latest}"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
CONFIG_DIR="${CONFIG_DIR:-/etc/sing-box}"
SERVICE_USER="${SERVICE_USER:-root}"

log_info()    { echo "[INFO] $*" >&2; }
log_success() { echo "[OK]   $*" >&2; }
log_warn()    { echo "[WARN] $*" >&2; }
log_error()   { echo "[ERR]  $*" >&2; }
log_step()    { echo "==> $*" >&2; }

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This command requires root privileges"
        log_error "Run: sudo $0"
        exit 1
    fi
}

get_arch() {
    local m
    m=$(uname -m)
    case "$m" in
        x86_64|amd64) echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        armv7l) echo "armv7" ;;
        *) log_error "Unsupported arch: $m"; exit 1; ;;
    esac
}

install_singbox() {
    check_root
    log_step "Installing sing-box"
    
    # Use official install script
    if command -v sing-box &>/dev/null; then
        log_info "sing-box already installed: $(sing-box version 2>/dev/null | head -1 || echo 'unknown')"
    else
        log_info "Downloading and installing sing-box via official script"
        if curl -fsSL https://sing-box.app/install.sh | bash; then
            log_success "sing-box installed: $(sing-box version 2>/dev/null | head -1 || echo 'unknown')"
        else
            log_error "sing-box installation failed"
            exit 1
        fi
    fi
}

setup_config_dir() {
    check_root
    log_step "Setting up config directory"
    
    mkdir -p "${CONFIG_DIR}"
    chmod 755 "${CONFIG_DIR}"
    log_success "Config directory ready: ${CONFIG_DIR}"
}

deploy_config() {
    check_root
    log_step "Validating configuration"
    
    if [ ! -f "${CONFIG_DIR}/config.json" ]; then
        log_error "Config file not found: ${CONFIG_DIR}/config.json"
        log_info "Please deploy config file first via Ansible"
        exit 1
    fi
    
    if [ ! -r "${CONFIG_DIR}/config.json" ]; then
        log_error "Cannot read config file: ${CONFIG_DIR}/config.json"
        exit 1
    fi
    
    if sing-box check -c "${CONFIG_DIR}/config.json" &>/dev/null; then
        log_success "Configuration validated"
    else
        log_error "Configuration validation failed"
        sing-box check -c "${CONFIG_DIR}/config.json" 2>&1 || true
        exit 1
    fi
}

setup_systemd() {
    check_root
    log_step "Setting up systemd service"
    
    # sing-box install script already creates systemd service
    if systemctl is-enabled sing-box &>/dev/null; then
        log_success "systemd service already exists"
    else
        log_warn "systemd service not found, may need manual setup"
    fi
    
    systemctl daemon-reload
    systemctl enable sing-box
    log_success "systemd service enabled"
}

configure_firewall() {
    check_root
    log_step "Configuring firewall"
    
    if ! command -v ufw &>/dev/null; then
        log_warn "ufw not installed, skipping firewall configuration"
        return 0
    fi
    
    ufw allow 22/tcp comment 'SSH' 2>/dev/null || true
    
    local port=443
    if [ -f "${CONFIG_DIR}/config.json" ] && command -v jq &>/dev/null; then
        port=$(jq -r '.inbounds[0].listen_port // 443' "${CONFIG_DIR}/config.json" 2>/dev/null || echo 443)
    fi
    
    ufw allow "${port}/tcp" comment 'sing-box' 2>/dev/null || true
    
    if ! ufw status | grep -q "Status: active"; then
        echo "y" | ufw enable 2>/dev/null || true
    fi
    
    log_success "Firewall configured (port ${port})"
}

optimize_system() {
    check_root
    log_step "Optimizing system parameters"
    
    if ! sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q bbr; then
        log_info "Enabling BBR congestion control"
        sysctl -w net.core.default_qdisc=fq
        sysctl -w net.ipv4.tcp_congestion_control=bbr
        
        if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf 2>/dev/null; then
            cat >> /etc/sysctl.conf <<EOF

# BBR congestion control
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
        fi
        log_success "BBR enabled"
    else
        log_info "BBR already enabled"
    fi
    
    log_info "Optimizing TCP buffers"
    sysctl -w net.core.rmem_max=16777216 2>/dev/null || true
    sysctl -w net.core.wmem_max=16777216 2>/dev/null || true
    sysctl -w net.ipv4.tcp_rmem="4096 87380 16777216" 2>/dev/null || true
    sysctl -w net.ipv4.tcp_wmem="4096 65536 16777216" 2>/dev/null || true
    
    log_info "Optimizing connection tracking"
    sysctl -w net.netfilter.nf_conntrack_max=1048576 2>/dev/null || true
    sysctl -w net.nf_conntrack_max=1048576 2>/dev/null || true
    
    log_success "System optimized"
}

start_service() {
    check_root
    log_step "Starting sing-box service"
    
    if systemctl is-active --quiet sing-box 2>/dev/null; then
        log_warn "sing-box service is already running"
        return 0
    fi
    
    systemctl start sing-box
    sleep 2
    
    if systemctl is-active --quiet sing-box; then
        log_success "sing-box service started"
    else
        log_error "sing-box service failed to start"
        log_error "Check logs with: journalctl -u sing-box -n 50"
        systemctl status sing-box --no-pager || true
        exit 1
    fi
}

stop_service() {
    check_root
    log_step "Stopping sing-box service"
    
    systemctl stop sing-box
    log_success "sing-box service stopped"
}

restart_service() {
    check_root
    log_step "Restarting sing-box service"
    
    systemctl restart sing-box
    sleep 2
    
    if systemctl is-active --quiet sing-box; then
        log_success "sing-box service restarted"
    else
        log_error "sing-box service failed to restart"
        log_error "Check logs with: journalctl -u sing-box -n 50"
        systemctl status sing-box --no-pager || true
        exit 1
    fi
}

status_service() {
    log_step "sing-box service status"
    
    if ! systemctl is-enabled sing-box &>/dev/null; then
        log_error "sing-box service not installed"
        exit 1
    fi
    
    systemctl status sing-box --no-pager || true
    
    echo ""
    log_step "Port listening"
    if command -v ss &>/dev/null; then
        ss -tlnp | grep sing-box || log_warn "No listening ports found"
    else
        netstat -tlnp 2>/dev/null | grep sing-box || log_warn "No listening ports found"
    fi
}

update_singbox() {
    check_root
    log_step "Updating sing-box"
    
    if ! command -v sing-box &>/dev/null; then
        log_error "sing-box not installed"
        log_info "Run: sudo $0 install"
        exit 1
    fi
    
    local old_version
    old_version=$(sing-box version 2>/dev/null | head -1 || echo "unknown")
    log_info "Current version: ${old_version}"
    
    if systemctl is-active --quiet sing-box 2>/dev/null; then
        systemctl stop sing-box
        log_info "Service stopped"
    fi
    
    log_info "Downloading and installing latest sing-box"
    if curl -fsSL https://sing-box.app/install.sh | bash; then
        local new_version
        new_version=$(sing-box version 2>/dev/null | head -1 || echo "unknown")
        log_success "Updated to: ${new_version}"
        
        systemctl start sing-box
        sleep 2
        
        if systemctl is-active --quiet sing-box; then
            log_success "Service restarted successfully"
        else
            log_error "Service failed to start after update"
            systemctl status sing-box --no-pager || true
            exit 1
        fi
    else
        log_error "Update failed"
        log_warn "Attempting to restart with old version"
        systemctl start sing-box || true
        exit 1
    fi
}

update_config() {
    check_root
    log_step "Updating configuration"
    
    log_info "Please deploy new config via Ansible, then run: sudo $0 restart"
}

uninstall() {
    check_root
    log_step "Uninstalling sing-box"
    
    if systemctl is-active --quiet sing-box 2>/dev/null; then
        systemctl stop sing-box
        log_info "Service stopped"
    fi
    
    if systemctl is-enabled --quiet sing-box 2>/dev/null; then
        systemctl disable sing-box
        log_info "Service disabled"
    fi
    
    if [ -f "${INSTALL_DIR}/sing-box" ]; then
        rm -f "${INSTALL_DIR}/sing-box"
        log_info "Binary removed"
    else
        log_warn "Binary not found: ${INSTALL_DIR}/sing-box"
    fi
    
    for service_file in /etc/systemd/system/sing-box.service /lib/systemd/system/sing-box.service; do
        if [ -f "$service_file" ]; then
            rm -f "$service_file"
            log_info "Removed: $service_file"
        fi
    done
    
    systemctl daemon-reload
    
    log_warn "Config directory preserved: ${CONFIG_DIR}"
    log_warn "To remove config: sudo rm -rf ${CONFIG_DIR}"
    
    log_success "sing-box uninstalled"
}

show_help() {
    cat <<EOF
sing-box management script

Usage: sudo $0 <command>

Commands:
  install           Install sing-box binary and setup service
  start             Start sing-box service (validates config first)
  stop              Stop sing-box service
  restart           Restart sing-box service (validates config first)
  status            Show service status and listening ports
  update-singbox    Update sing-box to latest version
  update-config     Update configuration (via Ansible)
  optimize-system   Optimize system parameters (BBR, TCP buffers, conntrack)
  uninstall         Uninstall sing-box (preserves config directory)
  help              Show this help message

Environment Variables:
  SINGBOX_VERSION   sing-box version to install (default: latest)
  INSTALL_DIR       Binary installation directory (default: /usr/local/bin)
  CONFIG_DIR        Configuration directory (default: /etc/sing-box)
  SERVICE_USER      Service user (default: root)

Examples:
  # Full installation workflow
  sudo $0 install
  sudo $0 optimize-system
  # Deploy config.json via Ansible to ${CONFIG_DIR}/
  sudo $0 start

  # Update sing-box
  sudo $0 update-singbox
  sudo $0 restart

  # Maintenance
  sudo $0 status
  journalctl -u sing-box -f

Notes:
  - Configuration must be deployed via Ansible before starting
  - Config validation runs automatically before start/restart
  - Firewall (ufw) is configured automatically if available
  - BBR optimization requires kernel 4.9+ (Ubuntu 18.04+)

EOF
}

main() {
    local cmd="${1:-help}"
    
    case "$cmd" in
        install)
            install_singbox
            setup_config_dir
            setup_systemd
            ;;
        start)
            deploy_config
            configure_firewall
            start_service
            ;;
        stop)
            stop_service
            ;;
        restart)
            deploy_config
            restart_service
            ;;
        status)
            status_service
            ;;
        update-singbox)
            update_singbox
            ;;
        update-config)
            update_config
            ;;
        optimize-system)
            optimize_system
            ;;
        uninstall)
            uninstall
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "Unknown command: $cmd"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
