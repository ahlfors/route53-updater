#!/bin/bash
###############################################################################
# Webhook 监听器 — 循环监听端口，每个连接交给 handler 处理
###############################################################################

set -uo pipefail

WEBHOOK_PORT="${WEBHOOK_PORT:-9090}"
export WEBHOOK_TOKEN="${WEBHOOK_TOKEN:?WEBHOOK_TOKEN is required}"
export IP_CACHE_FILE="${IP_CACHE_FILE:-/app/data/new_public_ip.txt}"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WEBHOOK] Listening on port ${WEBHOOK_PORT}..."

while true; do
    # -e 指定外部脚本处理每个连接，环境变量自动继承
    ncat -l -p "$WEBHOOK_PORT" -e /app/scripts/webhook-handler.sh 2>/dev/null
    sleep 0.1
done