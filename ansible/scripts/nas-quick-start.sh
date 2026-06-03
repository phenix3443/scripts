#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_DIR="${PROJECT_ROOT}/ansible"

echo "=========================================="
echo "NAS Quick Start - OpenMediaVault Setup"
echo "=========================================="
echo ""

# Check if running from correct location
if [ ! -f "${ANSIBLE_DIR}/ansible.cfg" ]; then
    echo "Error: Must run from home-lab repository root"
    exit 1
fi

# Check if ansible is installed
if ! command -v ansible-playbook &> /dev/null; then
    echo "Error: Ansible is not installed"
    echo "Install with: pip3 install ansible"
    exit 1
fi

# Check if inventory exists
INVENTORY="${ANSIBLE_DIR}/inventory/nas.yml"
if [ ! -f "$INVENTORY" ]; then
    echo "Error: Inventory file not found: $INVENTORY"
    echo "Please create it based on ansible/inventory/nas.yml"
    exit 1
fi

# Check if vault password file exists
VAULT_PASS="${ANSIBLE_DIR}/.vault_pass"
if [ ! -f "$VAULT_PASS" ]; then
    echo "Warning: Vault password file not found: $VAULT_PASS"
    echo "Creating a default one..."
    read -sp "Enter vault password: " vault_password
    echo ""
    echo "$vault_password" > "$VAULT_PASS"
    chmod 600 "$VAULT_PASS"
fi

# Check if vault.yml exists
VAULT_FILE="${ANSIBLE_DIR}/group_vars/nas_servers/vault.yml"
if [ ! -f "$VAULT_FILE" ]; then
    echo "Warning: Vault file not found: $VAULT_FILE"
    echo "Please create it based on vault.yml.example and encrypt it"
    echo ""
    read -p "Do you want to create it now? (y/n) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        cp "${VAULT_FILE}.example" "$VAULT_FILE"
        echo "Created $VAULT_FILE from example"
        echo "Please edit it and add your Cloudflare Tunnel token"
        read -p "Press Enter to open editor..." -r
        ${EDITOR:-vim} "$VAULT_FILE"
        echo "Encrypting vault file..."
        ansible-vault encrypt "$VAULT_FILE" --vault-password-file "$VAULT_PASS"
    else
        echo "Skipping vault creation. You'll need to create it manually."
    fi
fi

echo ""
echo "=========================================="
echo "Deployment Options"
echo "=========================================="
echo "1. Full deployment (all stages)"
echo "2. Stage 0 only (Install OMV)"
echo "3. Stage 1 only (Configure monitoring)"
echo "4. Stage 2 only (Install Cloudflare Tunnel)"
echo "5. Verify deployment"
echo "6. Exit"
echo ""
read -p "Select option (1-6): " option

case $option in
    1)
        echo "Running full deployment..."
        echo ""
        echo "Stage 0: Installing OMV..."
        ansible-playbook -i "$INVENTORY" \
            "${ANSIBLE_DIR}/playbooks/nas/0-omv-install.yml" \
            --vault-password-file "$VAULT_PASS" \
            --ask-become-pass
        
        echo ""
        echo "Stage 1: Configuring monitoring..."
        ansible-playbook -i "$INVENTORY" \
            "${ANSIBLE_DIR}/playbooks/nas/1-omv-monitoring.yml" \
            --vault-password-file "$VAULT_PASS"
        
        echo ""
        echo "Stage 2: Installing Cloudflare Tunnel..."
        ansible-playbook -i "$INVENTORY" \
            "${ANSIBLE_DIR}/playbooks/nas/2-cloudflare-tunnel.yml" \
            --vault-password-file "$VAULT_PASS"
        ;;
    2)
        echo "Running Stage 0: Install OMV..."
        ansible-playbook -i "$INVENTORY" \
            "${ANSIBLE_DIR}/playbooks/nas/0-omv-install.yml" \
            --vault-password-file "$VAULT_PASS" \
            --ask-become-pass
        ;;
    3)
        echo "Running Stage 1: Configure monitoring..."
        ansible-playbook -i "$INVENTORY" \
            "${ANSIBLE_DIR}/playbooks/nas/1-omv-monitoring.yml" \
            --vault-password-file "$VAULT_PASS"
        ;;
    4)
        echo "Running Stage 2: Install Cloudflare Tunnel..."
        ansible-playbook -i "$INVENTORY" \
            "${ANSIBLE_DIR}/playbooks/nas/2-cloudflare-tunnel.yml" \
            --vault-password-file "$VAULT_PASS"
        ;;
    5)
        echo "Verifying deployment..."
        ansible -i "$INVENTORY" nas_servers -m shell \
            -a "sudo /usr/local/bin/nas-status.sh" \
            --vault-password-file "$VAULT_PASS"
        ;;
    6)
        echo "Exiting..."
        exit 0
        ;;
    *)
        echo "Invalid option"
        exit 1
        ;;
esac

echo ""
echo "=========================================="
echo "Deployment Complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Access OMV web interface: http://<your-pi-ip>"
echo "2. Login with: admin / openmediavault"
echo "3. CHANGE DEFAULT PASSWORD IMMEDIATELY"
echo "4. Configure Cloudflare Tunnel public hostname"
echo "5. Access via: https://nas.yourdomain.com"
echo ""
echo "Useful commands:"
echo "  ansible -i $INVENTORY nas_servers -m shell -a 'sudo /usr/local/bin/nas-status.sh'"
echo "  ssh <user>@<ip> sudo /usr/local/bin/nas-status.sh"
echo "  ssh <user>@<ip> sudo journalctl -u openmediavault-engined -f"
echo ""
