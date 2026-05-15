#!/bin/bash
###############################################################################
# 轻量 HTTP Webhook 接收器
#
# 接收 POST 请求，验证 Token，将 IP 写入缓存文件
# 使用 ncat 监听，无需 nginx/python 等重型依赖
#
# 请求格式:
#   POST / HTTP/1.1
#   Authorization: Bearer <WEBHOOK_TOKEN>
#   Content-Type: application/json
#   {"ip": "1.2.3.4"}
###############################################################################

set -uo pipefail

WEBHOOK_PORT="${WEBHOOK_PORT:-9090}"
WEBHOOK_TOKEN="${WEBHOOK_TOKEN:?WEBHOOK_TOKEN is required}"
IP_CACHE_FILE="${IP_CACHE_FILE:-/app/data/new_public_ip.txt}"
LOG_PREFIX_FN() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WEBHOOK]"; }

echo "$(LOG_PREFIX_FN) Starting webhook listener on port ${WEBHOOK_PORT}..."

while true; do
    # ncat 监听单次连接，读取完整 HTTP 请求后处理
    ncat -l -p "$WEBHOOK_PORT" -c '
        # 读取请求头
        REQUEST_LINE=""
        CONTENT_LENGTH=0
        AUTH_HEADER=""
        while IFS= read -r line; do
            line=$(echo "$line" | tr -d "\r")
            # 首行是请求行
            if [ -z "$REQUEST_LINE" ]; then
                REQUEST_LINE="$line"
            fi
            # 解析 Content-Length
            case "$line" in
                Content-Length:*|content-length:*)
                    CONTENT_LENGTH=$(echo "$line" | awk -F": " "{print \$2}" | tr -d " ")
                    ;;
                Authorization:*|authorization:*)
                    AUTH_HEADER=$(echo "$line" | sed "s/^[Aa]uthorization: *//")
                    ;;
            esac
            # 空行表示 header 结束
            if [ -z "$line" ]; then
                break
            fi
        done

        # 读取 body
        BODY=""
        if [ "$CONTENT_LENGTH" -gt 0 ] 2>/dev/null; then
            BODY=$(head -c "$CONTENT_LENGTH")
        fi

        # ---------- 路由处理 ----------

        # 健康检查: GET /health
        if echo "$REQUEST_LINE" | grep -q "^GET /health"; then
            RESPONSE="{\"status\":\"ok\",\"time\":\"$(date -Iseconds)\"}"
            echo -e "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: ${#RESPONSE}\r\nConnection: close\r\n\r\n${RESPONSE}"
            exit 0
        fi

        # 仅接受 POST /
        if ! echo "$REQUEST_LINE" | grep -q "^POST"; then
            RESPONSE="{\"error\":\"method not allowed\"}"
            echo -e "HTTP/1.1 405 Method Not Allowed\r\nContent-Type: application/json\r\nContent-Length: ${#RESPONSE}\r\nConnection: close\r\n\r\n${RESPONSE}"
            exit 0
        fi

        # Token 验证
        EXPECTED_TOKEN="Bearer '"${WEBHOOK_TOKEN}"'"
        if [ "$AUTH_HEADER" != "$EXPECTED_TOKEN" ]; then
            RESPONSE="{\"error\":\"unauthorized\"}"
            echo -e "HTTP/1.1 401 Unauthorized\r\nContent-Type: application/json\r\nContent-Length: ${#RESPONSE}\r\nConnection: close\r\n\r\n${RESPONSE}"
            exit 0
        fi

        # 解析 IP
        NEW_IP=$(echo "$BODY" | grep -oE "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}" | head -1)

        if [ -z "$NEW_IP" ]; then
            RESPONSE="{\"error\":\"invalid ip in body\"}"
            echo -e "HTTP/1.1 400 Bad Request\r\nContent-Type: application/json\r\nContent-Length: ${#RESPONSE}\r\nConnection: close\r\n\r\n${RESPONSE}"
            exit 0
        fi

        # 写入 IP 缓存文件
        echo "$NEW_IP" > "'"${IP_CACHE_FILE}"'"

        RESPONSE="{\"status\":\"accepted\",\"ip\":\"${NEW_IP}\"}"
        echo -e "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: ${#RESPONSE}\r\nConnection: close\r\n\r\n${RESPONSE}"
    ' 2>/dev/null

    # 短暂等待避免 CPU 空转
    sleep 0.1
done