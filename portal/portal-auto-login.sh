#!/usr/bin/env bash
# 公司门户自动检测与登录：检测是否被重定向到门户页，需要时自动 POST 登录。
# 配置见同目录 portal.conf，凭证见 portal.secret 或环境变量 PORTAL_USERNAME / PORTAL_PASSWORD。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_FILE="${SCRIPT_DIR}/portal.conf"
SECRET_FILE="${SCRIPT_DIR}/portal.secret"
COOKIE_FILE=""
DEBUG="${DEBUG:-0}"

cleanup() {
    [[ -n "$COOKIE_FILE" && -f "$COOKIE_FILE" ]] && rm -f "$COOKIE_FILE"
}
trap cleanup EXIT

debug() {
    [[ "$DEBUG" == "1" ]] && echo "[DEBUG] $*" >&2
}

log_info() {
    echo "[portal] $*" >&2
}

log_ok() {
    echo "[portal] ✓ $*" >&2
}

log_err() {
    echo "[portal] ✗ $*" >&2
}

# 从 portal.conf 读取配置（支持 # 注释和 KEY=value）
load_config() {
    if [[ ! -f "$CONF_FILE" ]]; then
        log_err "配置文件不存在: $CONF_FILE (可复制 portal.conf.example 并修改)"
        return 1
    fi
    while IFS= read -r line; do
        line="${line%%#*}"
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "$line" ]] && continue
        if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
            export "${BASH_REMATCH[1]}=${BASH_REMATCH[2]}"
        fi
    done < "$CONF_FILE"
    return 0
}

# 从 portal.secret 或环境变量读取用户名密码
load_credentials() {
    if [[ -f "$SECRET_FILE" ]]; then
        # 格式: PORTAL_USERNAME=xxx 与 PORTAL_PASSWORD=xxx 或 USERNAME= / PASSWORD=
        while IFS= read -r line; do
            line="${line%%#*}"
            [[ -z "${line// }" ]] && continue
            if [[ "$line" =~ ^(PORTAL_USERNAME|PORTAL_PASSWORD|USERNAME|PASSWORD)=(.*)$ ]]; then
                export "${BASH_REMATCH[1]}=${BASH_REMATCH[2]}"
            fi
        done < "$SECRET_FILE"
    fi
    PORTAL_USERNAME="${PORTAL_USERNAME:-${USERNAME:-}}"
    PORTAL_PASSWORD="${PORTAL_PASSWORD:-${PASSWORD:-}}"
    if [[ -z "$PORTAL_USERNAME" || -z "$PORTAL_PASSWORD" ]]; then
        log_err "未配置凭证。请设置 portal.secret 或环境变量 PORTAL_USERNAME / PORTAL_PASSWORD"
        return 1
    fi
    return 0
}

# 检测是否需要登录：请求 PROBE_URL，若最终 URL 包含 PORTAL_URL_PATTERN 则认为需要登录
need_login() {
    local effective_url
    effective_url=$(curl -sI -L -o /dev/null -w "%{url_effective}" ${CURL_OPTS:-} --connect-timeout 10 --max-time 15 "$PROBE_URL" 2>/dev/null || true)
    debug "探测 $PROBE_URL -> 最终 URL: $effective_url"
    if [[ "$effective_url" == *"${PORTAL_URL_PATTERN}"* ]]; then
        return 0
    fi
    return 1
}

# 执行登录：GET 登录页拿 Cookie，再 POST 提交表单
do_login() {
    local login_url="$LOGIN_URL"
    local username_field="${USERNAME_FIELD:-username}"
    local password_field="${PASSWORD_FIELD:-password}"
    local post_data
    post_data="${username_field}=$(printf '%s' "$PORTAL_USERNAME" | sed 's/&/%26/g')&${password_field}=$(printf '%s' "$PORTAL_PASSWORD" | sed 's/&/%26/g')"
    [[ -n "${EXTRA_POST_PARAMS:-}" ]] && post_data="${EXTRA_POST_PARAMS}&${post_data}"

    COOKIE_FILE=$(mktemp)
    debug "GET 登录页: $login_url"
    if ! curl -s -c "$COOKIE_FILE" -o /dev/null ${CURL_OPTS:-} --connect-timeout 10 --max-time 15 "$login_url"; then
        log_err "请求登录页失败"
        return 1
    fi
    debug "POST 登录: $login_url"
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -X POST \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "$post_data" ${CURL_OPTS:-} --connect-timeout 10 --max-time 15 "$login_url" 2>/dev/null || echo "000")
    debug "POST 响应码: $http_code"
    if [[ "$http_code" =~ ^(200|302|301|303)$ ]]; then
        return 0
    fi
    log_err "登录请求返回 HTTP $http_code"
    return 1
}

usage() {
    cat <<USAGE
Usage: $0 [check|login|run]

  check  仅检测是否需要登录（需登录时退出码 1）
  login  强制尝试登录一次
  run    先检测，需要时再登录（默认）

环境变量:
  DEBUG=1           输出调试信息
  CURL_OPTS        传给 curl 的额外参数，如 -k 跳过证书校验（门户常为自签名）
USAGE
}

main() {
    local cmd="${1:-run}"

    if [[ "$cmd" == "-h" || "$cmd" == "--help" ]]; then
        usage
        exit 0
    fi

    if ! load_config; then
        exit 1
    fi

    # 若配置中 LOGIN_ENDPOINT 以 http 开头则视为完整 URL，否则拼在 PORTAL_BASE_URL 后
    if [[ "${LOGIN_ENDPOINT:-}" == http://* || "${LOGIN_ENDPOINT:-}" == https://* ]]; then
        LOGIN_URL="${LOGIN_ENDPOINT}"
    else
        LOGIN_URL="${PORTAL_BASE_URL%/}${LOGIN_ENDPOINT:-/}"
    fi

    case "$cmd" in
        check)
            if need_login; then
                log_info "需要登录"
                exit 1
            else
                log_ok "已联网，无需登录"
                exit 0
            fi
            ;;
        login)
            if ! load_credentials; then
                exit 1
            fi
            if do_login; then
                if need_login; then
                    log_err "登录后仍被重定向到门户，可能账号错误或需验证码"
                    exit 1
                fi
                log_ok "登录成功"
                exit 0
            fi
            exit 1
            ;;
        run)
            if ! need_login; then
                log_ok "已联网，无需登录"
                exit 0
            fi
            log_info "检测到门户重定向，尝试自动登录..."
            if ! load_credentials; then
                exit 1
            fi
            if do_login; then
                if need_login; then
                    log_err "登录后仍被重定向到门户"
                    exit 1
                fi
                log_ok "登录成功"
                exit 0
            fi
            exit 1
            ;;
        *)
            log_err "未知命令: $cmd"
            usage
            exit 1
            ;;
    esac
}

main "$@"
