#!/usr/bin/env bash
set -e

### ========= Config =========
PORT=443
DEST_DOMAIN="www.cloudflare.com"
SERVER_NAME="www.cloudflare.com"
SHORT_ID="abcd"
XRAY_IMAGE="ghcr.io/xtls/xray-core:latest"
XRAY_CONF_DIR="${XRAY_CONF_DIR:-/opt/xray}"
XRAY_CONF="${XRAY_CONF_DIR}/config.json"
CONTAINER_NAME="xray-reality"

UUID=""
PRIVATE_KEY=""
PUBLIC_KEY=""

check_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "Run as root (sudo)"
    exit 1
  fi
}

install_deps() {
  echo "==> Install dependencies"
  apt update -qq
  apt install -y curl jq
}

ensure_docker() {
  if command -v docker &>/dev/null; then
    return 0
  fi
  echo "==> Install Docker"
  curl -fsSL https://get.docker.com | sh
}

generate_uuid() {
  UUID=$(cat /proc/sys/kernel/random/uuid)
}

generate_reality_keys() {
  echo "==> Generate REALITY keys"
  local key_json
  key_json=$(docker run --rm "$XRAY_IMAGE" x25519 -json)
  PRIVATE_KEY=$(echo "$key_json" | jq -r '.privateKey')
  PUBLIC_KEY=$(echo "$key_json" | jq -r '.publicKey')
}

write_config() {
  echo "==> Write config ${XRAY_CONF}"
  mkdir -p "$XRAY_CONF_DIR"
  cat > "$XRAY_CONF" <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": ${PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${DEST_DOMAIN}:443",
          "xver": 0,
          "serverNames": ["${SERVER_NAME}"],
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": ["${SHORT_ID}"]
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
EOF
}

setup_firewall() {
  if ! command -v ufw &>/dev/null; then
    return 0
  fi
  echo "==> UFW allow ${PORT}/tcp"
  ufw allow "${PORT}"/tcp || true
}

run_container() {
  docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
  echo "==> Run Xray container"
  docker run -d \
    --name "$CONTAINER_NAME" \
    --restart unless-stopped \
    -p "${PORT}:${PORT}" \
    -v "${XRAY_CONF}:/etc/xray/config.json:ro" \
    "$XRAY_IMAGE" \
    run -c /etc/xray/config.json
  sleep 2
  docker ps --filter "name=${CONTAINER_NAME}" || true
}

print_client_info() {
  local ip
  ip=$(curl -s --connect-timeout 5 https://api.ipify.org || echo "YOUR_SERVER_IP")
  echo
  echo "================= Done ================="
  echo
  echo "IP        : ${ip}"
  echo "Port      : ${PORT}"
  echo "UUID      : ${UUID}"
  echo "PublicKey : ${PUBLIC_KEY}"
  echo "ShortID   : ${SHORT_ID}"
  echo
  echo "================= Clash ================="
  cat <<EOF

- name: xray-reality
  type: vless
  server: ${ip}
  port: ${PORT}
  uuid: ${UUID}
  network: tcp
  tls: true
  flow: xtls-rprx-vision
  servername: ${SERVER_NAME}
  reality-opts:
    public-key: ${PUBLIC_KEY}
    short-id: ${SHORT_ID}
  udp: true

EOF
  echo "============================================="
}

main() {
  check_root
  install_deps
  ensure_docker
  generate_uuid
  generate_reality_keys
  write_config
  setup_firewall
  run_container
  print_client_info
}

main "$@"
