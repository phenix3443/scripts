#!/usr/bin/env bash
set -euo pipefail

DEFAULT_PROXY="http://127.0.0.1:7890"
PROXY_URL=""
PROXY_HOST=""
PROXY_PORT=""
SSH_CONFIG="${HOME}/.ssh/config"
BLOCK_START="# >>> github-proxy (home-lab)"
BLOCK_END="# <<< github-proxy (home-lab)"

usage() {
  cat <<USAGE
Usage: $0 <install|uninstall|status> [proxy_url]

Commands:
  install   - Set GitHub HTTPS and SSH to use proxy (proxy_url optional)
  uninstall - Remove proxy config
  status    - Show current proxy config

Examples:
  $0 install http://127.0.0.1:7890
  $0 install socks5://127.0.0.1:7890
  $0 uninstall
  $0 status

Default proxy: ${DEFAULT_PROXY}
USAGE
}

NC_X_OPT="connect"

parse_proxy_url() {
  local url="$1"
  if [[ "$url" =~ ^(https?|socks5?)://([^:/]+):([0-9]+)(/.*)?$ ]]; then
    PROXY_URL="$url"
    PROXY_HOST="${BASH_REMATCH[2]}"
    PROXY_PORT="${BASH_REMATCH[3]}"
    case "${BASH_REMATCH[1]}" in
      socks5) NC_X_OPT="5" ;;
      socks4) NC_X_OPT="4" ;;
      *) NC_X_OPT="connect" ;;
    esac
    return 0
  fi
  echo "Invalid proxy URL: $url (expected e.g. http://host:port or socks5://host:port)" >&2
  return 1
}

ensure_ssh_config() {
  mkdir -p "$(dirname "${SSH_CONFIG}")"
  touch "${SSH_CONFIG}"
  chmod 600 "${SSH_CONFIG}"
}

install_git_https() {
  local url="$PROXY_URL"
  if [[ "$url" =~ ^socks ]]; then
    url="socks5://${PROXY_HOST}:${PROXY_PORT}"
  elif [[ ! "$url" =~ ^https?:// ]]; then
    url="http://${PROXY_HOST}:${PROXY_PORT}"
  fi
  git config --global http.https://github.com.proxy "$url"
  git config --global https.https://github.com.proxy "$url"
}

uninstall_git_https() {
  git config --global --unset-all http.https://github.com.proxy || true
  git config --global --unset-all https.https://github.com.proxy || true
}

install_ssh_block() {
  ensure_ssh_config

  # Remove any existing block first
  awk -v start="${BLOCK_START}" -v end="${BLOCK_END}" '
    $0 == start {skip=1; next}
    $0 == end {skip=0; next}
    !skip {print}
  ' "${SSH_CONFIG}" > "${SSH_CONFIG}.tmp"

  cat >>"${SSH_CONFIG}.tmp" <<EOF_BLOCK
${BLOCK_START}
Host github.com
  HostName github.com
  User git
  ProxyCommand nc -X ${NC_X_OPT} -x ${PROXY_HOST}:${PROXY_PORT} %h %p
${BLOCK_END}
EOF_BLOCK

  mv "${SSH_CONFIG}.tmp" "${SSH_CONFIG}"
  chmod 600 "${SSH_CONFIG}"
}

uninstall_ssh_block() {
  if [[ ! -f "${SSH_CONFIG}" ]]; then
    return 0
  fi

  awk -v start="${BLOCK_START}" -v end="${BLOCK_END}" '
    $0 == start {skip=1; next}
    $0 == end {skip=0; next}
    !skip {print}
  ' "${SSH_CONFIG}" > "${SSH_CONFIG}.tmp"

  mv "${SSH_CONFIG}.tmp" "${SSH_CONFIG}"
  chmod 600 "${SSH_CONFIG}"
}

show_status() {
  echo "HTTPS proxy (git config):"
  git config --global --get-all http.https://github.com.proxy || echo "(not set)"
  git config --global --get-all https.https://github.com.proxy || echo "(not set)"

  echo
  echo "SSH config block:"
  if [[ -f "${SSH_CONFIG}" ]]; then
    awk -v start="${BLOCK_START}" -v end="${BLOCK_END}" '
      $0 == start {show=1}
      show {print}
      $0 == end {show=0}
    ' "${SSH_CONFIG}" || true
  else
    echo "(no ~/.ssh/config)"
  fi
}

main() {
  if [[ $# -lt 1 ]]; then
    usage
    exit 1
  fi

  cmd="$1"; shift
  case "${cmd}" in
    install)
      local proxy_arg="${1:-$DEFAULT_PROXY}"
      parse_proxy_url "$proxy_arg" || exit 1
      install_git_https
      install_ssh_block
      echo "Installed GitHub HTTPS+SSH proxy: ${PROXY_URL}"
      ;;
    uninstall)
      uninstall_git_https
      uninstall_ssh_block
      echo "Removed GitHub HTTPS+SSH proxy config"
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
}

main "$@"
