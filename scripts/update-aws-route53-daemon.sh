#!/bin/bash
###############################################################################
# AWS Route53 自动更新守护脚本（由 cron 定时调用）
#
# 功能：
#   1. 检查 IP 缓存文件是否存在
#   2. 存在则调用 update-aws-route53.sh 更新域名
#   3. 更新成功后发送飞书通知
###############################################################################

set -uo pipefail

# ================= 配置区 =================
FEISHU_WEBHOOK="https://open.feishu.cn/open-apis/bot/v2/hook/${FEISHU_WEBHOOK_TOKEN}"
IP_CACHE_FILE="${IP_CACHE_FILE:-/host-tmp/new_public_ip.txt}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_PREFIX="[$(date '+%Y-%m-%d %H:%M:%S')]"

# ================= 主逻辑 =================

if [ -f "$IP_CACHE_FILE" ]; then
    NEW_IP=$(cat "$IP_CACHE_FILE")

    # 校验 IP 格式
    if ! echo "$NEW_IP" | grep -qE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'; then
        echo "${LOG_PREFIX} ❌ 无效的 IP 格式: ${NEW_IP}"
        exit 1
    fi

    echo "${LOG_PREFIX} 检测到新 IP: ${NEW_IP}，开始更新 Route53..."

    # 调用更新脚本（绝对路径 + 引号传参）
    if /bin/bash "${SCRIPT_DIR}/update-aws-route53.sh" "$NEW_IP"; then
        rm -f "$IP_CACHE_FILE"
        UPDATE_TIME=$(date "+%Y-%m-%d %H:%M:%S")

        echo "${LOG_PREFIX} ✅ Route53 更新成功，发送飞书通知..."

        # 构造飞书卡片 JSON
        PAYLOAD=$(cat <<EOF
{
    "msg_type": "interactive",
    "card": {
        "config": { "wide_screen_mode": true },
        "header": {
            "template": "turquoise",
            "title": { "content": "🌍 更新${TARGET_NAME} ROUTE53 提醒", "tag": "plain_text" }
        },
        "elements": [
            {
                "tag": "div",
                "text": { "content": "**A记录更新成功！**", "tag": "lark_md" }
            },
            { "tag": "hr" },
            {
                "tag": "div",
                "fields": [
                    { "is_short": true, "text": { "tag": "lark_md", "content": "**新公网 IP：**\n${NEW_IP}" } }
                ]
            },
            {
                "tag": "note",
                "elements": [{ "tag": "plain_text", "content": "📍 更新于 ${UPDATE_TIME}" }]
            }
        ]
    }
}
EOF
)
        # 发送飞书通知
        RESP=$(curl -s -w "\n%{http_code}" -X POST \
            -H "Content-Type: application/json" \
            -d "$PAYLOAD" \
            "$FEISHU_WEBHOOK" 2>&1)

        RESP_CODE=$(echo "$RESP" | tail -n1)
        RESP_BODY=$(echo "$RESP" | sed '$d')

        if [ "$RESP_CODE" = "200" ]; then
            echo "${LOG_PREFIX} ✅ 飞书通知发送成功"
        else
            echo "${LOG_PREFIX} ❌ 飞书通知发送失败 (HTTP ${RESP_CODE}): ${RESP_BODY}"
        fi
    else
        echo "${LOG_PREFIX} ❌ Route53 更新失败，保留 IP 缓存文件以供重试"
        exit 1
    fi
else
    echo "${LOG_PREFIX} 无新 IP 文件，跳过"
fi