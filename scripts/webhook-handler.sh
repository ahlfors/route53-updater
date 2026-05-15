#!/bin/bash
###############################################################################
# Webhook 请求处理器
# 由 ncat -e 调用，stdin/stdout 直接连接到 TCP socket
# 环境变量 WEBHOOK_TOKEN / IP_CACHE_FILE 由父进程传入
###############################################################################

# ---------- 读取 HTTP 请求头 ----------
REQUEST_LINE=""
CONTENT_LENGTH=0
AUTH_HEADER=""

while IFS= read -r line; do
    line="${line%%$'\r'}"

    # 首行是请求行
    if [ -z "$REQUEST_LINE" ]; then
        REQUEST_LINE="$line"
    fi

    # 解析关键 Header（大小写不敏感）
    header_lower=$(echo "$line" | tr '[:upper:]' '[:lower:]')
    case "$header_lower" in
        content-length:*)
            CONTENT_LENGTH=$(echo "$line" | cut -d':' -f2 | tr -d ' ')
            ;;
        authorization:*)
            AUTH_HEADER=$(echo "$line" | sed 's/^[Aa]uthorization: *//')
            ;;
    esac

    # 空行 = Header 结束
    if [ -z "$line" ]; then
        break
    fi
done

# ---------- 读取 Body ----------
BODY=""
if [ "$CONTENT_LENGTH" -gt 0 ] 2>/dev/null; then
    BODY=$(dd bs=1 count="$CONTENT_LENGTH" 2>/dev/null)
fi

# ---------- 辅助：发送响应 ----------
send_response() {
    local code="$1"
    local status="$2"
    local body="$3"
    local len=${#body}
    printf "HTTP/1.1 %s %s\r\n" "$code" "$status"
    printf "Content-Type: application/json\r\n"
    printf "Content-Length: %d\r\n" "$len"
    printf "Connection: close\r\n"
    printf "\r\n"
    printf "%s" "$body"
}

# ---------- 路由：GET /health ----------
if echo "$REQUEST_LINE" | grep -q "^GET /health"; then
    RESP="{\"status\":\"ok\",\"time\":\"$(date -Iseconds)\"}"
    send_response 200 "OK" "$RESP"
    exit 0
fi

# ---------- 路由：仅接受 POST ----------
if ! echo "$REQUEST_LINE" | grep -q "^POST"; then
    send_response 405 "Method Not Allowed" '{"error":"method not allowed"}'
    exit 0
fi

# ---------- Token 验证 ----------
EXPECTED="Bearer ${WEBHOOK_TOKEN}"
if [ "$AUTH_HEADER" != "$EXPECTED" ]; then
    send_response 401 "Unauthorized" '{"error":"unauthorized"}'
    exit 0
fi

# ---------- 解析并校验 IP ----------
NEW_IP=$(echo "$BODY" | grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -1)

if [ -z "$NEW_IP" ]; then
    send_response 400 "Bad Request" '{"error":"invalid or missing ip"}'
    exit 0
fi

# ---------- 写入 IP 缓存文件 ----------
echo "$NEW_IP" > "${IP_CACHE_FILE}"

RESP="{\"status\":\"accepted\",\"ip\":\"${NEW_IP}\"}"
send_response 200 "OK" "$RESP"
exit 0