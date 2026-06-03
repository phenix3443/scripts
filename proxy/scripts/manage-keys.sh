#!/bin/bash
#
# manage-keys.sh - Manage vaulted ppanel-node host variables
#
# Description:
#   Maintains the host_vars files consumed by ansible/playbooks/vps/0-ppanel-node.yml.
#   Each VPS keeps its own ppanel_node_server_id / ppanel_node_secret_key alongside
#   ansible_become_password in ansible/inventory/host_vars/<host>.yml.
#
# Usage:
#   ./proxy/scripts/manage-keys.sh <command> [options]
#
# Commands:
#   list
#   show <host>
#   set <host> --server-id ID --secret-key KEY [--api-host URL] [--become-password PASS]
#   delete <host>
#   template <host>
#
# Dependencies:
#   - ansible-vault
#   - yq (mikefarah/yq)
#

set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HOST_VARS_DIR="${REPO_ROOT}/ansible/inventory/host_vars"
VAULT_PASS_FILE="${REPO_ROOT}/ansible/.vault_pass"
INVENTORY_FILE="${REPO_ROOT}/ansible/inventory/vps.yml"
DEFAULT_API_HOST="https://admin-ppanel.panghuli.tech"

log_info()    { echo "[INFO] $*" >&2; }
log_success() { echo "[OK]   $*" >&2; }
log_warn()    { echo "[WARN] $*" >&2; }
log_error()   { echo "[ERR]  $*" >&2; }

usage() {
    cat <<'EOF'
Usage: ./proxy/scripts/manage-keys.sh <command> [options]

Commands:
  list
      List VPS hosts from ansible/inventory/vps.yml and whether host_vars exists.

  show <host>
      Decrypt and show ansible/inventory/host_vars/<host>.yml.

  set <host> --server-id ID --secret-key KEY [--api-host URL] [--become-password PASS]
      Create or update ansible/inventory/host_vars/<host>.yml with the variables
      required by the ppanel-node playbook.

  delete <host>
      Remove ansible/inventory/host_vars/<host>.yml after confirmation.

  template <host>
      Print an unencrypted example for ansible/inventory/host_vars/<host>.yml.
EOF
    exit 1
}

check_dependencies() {
    local missing=()

    for cmd in ansible-vault yq; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing dependencies: ${missing[*]}"
        log_error "Install with:"
        log_error "  macOS: brew install ansible yq"
        log_error "  Linux: apt install ansible && install mikefarah/yq"
        exit 1
    fi

    if [ ! -f "$VAULT_PASS_FILE" ]; then
        log_error "Vault password file not found: $VAULT_PASS_FILE"
        exit 1
    fi
}

ensure_host_exists_in_inventory() {
    local host="$1"
    if ! yq -e ".all.children.vps_nodes.hosts | has(\"${host}\")" "$INVENTORY_FILE" >/dev/null 2>&1; then
        log_error "Host '${host}' not found in ${INVENTORY_FILE}"
        exit 1
    fi
}

host_var_path() {
    local host="$1"
    echo "${HOST_VARS_DIR}/${host}.yml"
}

decrypt_file() {
    local file="$1"
    if [ ! -f "$file" ]; then
        echo ""
        return 0
    fi

    ansible-vault decrypt "$file" --vault-password-file "$VAULT_PASS_FILE" --output -
}

encrypt_content_to_file() {
    local content="$1"
    local file="$2"
    local tmp_plain

    tmp_plain="$(mktemp)"
    trap 'rm -f "$tmp_plain"' RETURN
    printf '%s\n' "$content" > "$tmp_plain"
    ansible-vault encrypt "$tmp_plain" --vault-password-file "$VAULT_PASS_FILE" --output "$file"
    rm -f "$tmp_plain"
    trap - RETURN
}

build_template() {
    local host="$1"
    cat <<EOF
# Host-specific sensitive variables for ${host}
# Encrypt with:
#   ansible-vault encrypt ${host}.yml --vault-password-file ../.vault_pass

ansible_become_password: "your_sudo_password_here"
ppanel_node_server_id: 1
ppanel_node_secret_key: "replace_with_actual_secret_key"
ppanel_node_api_host: ${DEFAULT_API_HOST}

# Optional: override default ansible_user
# ansible_user: lsl
EOF
}

list_hosts() {
    local hosts
    hosts=$(yq '.all.children.vps_nodes.hosts | keys | .[]' "$INVENTORY_FILE")

    echo ""
    for host in $hosts; do
        local file
        file="$(host_var_path "$host")"
        if [ -f "$file" ]; then
            echo "  ${host}  host_vars=present"
        else
            echo "  ${host}  host_vars=missing"
        fi
    done
    echo ""
}

show_host() {
    local host="$1"
    local file

    [ -z "$host" ] && usage
    ensure_host_exists_in_inventory "$host"
    file="$(host_var_path "$host")"

    if [ ! -f "$file" ]; then
        log_warn "Host vars file does not exist: $file"
        echo ""
        build_template "$host"
        echo ""
        return 0
    fi

    decrypt_file "$file"
}

set_host() {
    local host="$1"
    shift

    local server_id=""
    local secret_key=""
    local api_host=""
    local become_password=""
    local file
    local current=""
    local updated=""

    [ -z "$host" ] && usage
    ensure_host_exists_in_inventory "$host"
    file="$(host_var_path "$host")"

    while [ $# -gt 0 ]; do
        case "$1" in
            --server-id)
                server_id="$2"
                shift 2
                ;;
            --secret-key)
                secret_key="$2"
                shift 2
                ;;
            --api-host)
                api_host="$2"
                shift 2
                ;;
            --become-password)
                become_password="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                ;;
        esac
    done

    if [ -z "$server_id" ] || [ -z "$secret_key" ]; then
        log_error "set requires --server-id and --secret-key"
        exit 1
    fi

    if [ -f "$file" ]; then
        current="$(decrypt_file "$file")"
    else
        current="$(build_template "$host")"
    fi

    updated="$(printf '%s\n' "$current" | yq \
        ".ppanel_node_server_id = ${server_id} |
         .ppanel_node_secret_key = \"${secret_key}\"")"

    if [ -n "$api_host" ]; then
        updated="$(printf '%s\n' "$updated" | yq ".ppanel_node_api_host = \"${api_host}\"")"
    fi

    if [ -n "$become_password" ]; then
        updated="$(printf '%s\n' "$updated" | yq ".ansible_become_password = \"${become_password}\"")"
    fi

    mkdir -p "$HOST_VARS_DIR"
    encrypt_content_to_file "$updated" "$file"
    log_success "Updated ${file}"
}

delete_host() {
    local host="$1"
    local file

    [ -z "$host" ] && usage
    ensure_host_exists_in_inventory "$host"
    file="$(host_var_path "$host")"

    if [ ! -f "$file" ]; then
        log_warn "Nothing to delete: $file"
        return 0
    fi

    read -r -p "Delete ${file}? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        log_info "Cancelled"
        return 0
    fi

    rm -f "$file"
    log_success "Deleted ${file}"
}

template_host() {
    local host="$1"
    [ -z "$host" ] && usage
    ensure_host_exists_in_inventory "$host"
    build_template "$host"
}

main() {
    local command="${1:-}"
    shift || true

    [ -z "$command" ] && usage
    check_dependencies

    case "$command" in
        list)
            list_hosts
            ;;
        show)
            show_host "${1:-}"
            ;;
        set)
            set_host "${1:-}" "${@:2}"
            ;;
        delete)
            delete_host "${1:-}"
            ;;
        template)
            template_host "${1:-}"
            ;;
        *)
            usage
            ;;
    esac
}

main "$@"
