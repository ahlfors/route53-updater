#!/bin/bash
###############################################################################
# AWS Route53 批量更新 A 记录脚本
#
# 用法: ./update-aws-route53.sh <NEW_IP>
#
# 环境变量: ZONE_ID, RECORD_NAMES (空格分隔的域名列表)
###############################################################################

set -euo pipefail

RECORD_TYPE="A"
TTL=300
NEW_IP="$1"

# ==================== 参数校验 ====================

if [ -z "$NEW_IP" ]; then
    echo "❌ 错误: 未传入新 IP。"
    echo "用法: ./update-aws-route53.sh 1.2.3.4"
    exit 1
fi

if [ -z "${ZONE_ID:-}" ]; then
    echo "❌ 错误: ZONE_ID 环境变量未设置。"
    exit 1
fi

if [ -z "${RECORD_NAMES:-}" ]; then
    echo "❌ 错误: RECORD_NAMES 环境变量未设置。"
    exit 1
fi

# 将空格分隔的字符串解析为数组
read -ra RECORD_NAMES_ARRAY <<< "$RECORD_NAMES"

echo "正在准备批量更新以下域名至 $NEW_IP: ${RECORD_NAMES_ARRAY[*]}"

# ==================== 构造 JSON ====================

CHANGES_JSON=""
for NAME in "${RECORD_NAMES_ARRAY[@]}"; do
    CHANGE_ITEM=$(cat <<EOF
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "$NAME",
        "Type": "$RECORD_TYPE",
        "TTL": $TTL,
        "ResourceRecords": [{ "Value": "$NEW_IP" }]
      }
    }
EOF
)
    if [ -z "$CHANGES_JSON" ]; then
        CHANGES_JSON="$CHANGE_ITEM"
    else
        CHANGES_JSON="$CHANGES_JSON, $CHANGE_ITEM"
    fi
done

# 写入临时文件（避免 shell 转义问题）
BATCH_FILE="/tmp/route53-batch.json"
cat > "$BATCH_FILE" <<EOF
{
  "Comment": "Batch Update IP via Script",
  "Changes": [$CHANGES_JSON]
}
EOF

echo "生成的 JSON Batch："
cat "$BATCH_FILE"

# ==================== 执行 AWS API ====================
# 使用 file:// 协议传递 JSON，避免 --change-batch 直接传字符串的转义问题

RESPONSE=$(aws route53 change-resource-record-sets \
    --hosted-zone-id "$ZONE_ID" \
    --change-batch "file://${BATCH_FILE}" 2>&1)

rm -f "$BATCH_FILE"

# 结果检查
if [[ "$RESPONSE" == *"ChangeInfo"* ]]; then
    echo "✅ 批量更新成功！"
    echo "AWS 已受理，状态将在几分钟内同步。"
else
    echo "❌ 更新失败，AWS 返回错误："
    echo "$RESPONSE"
    exit 1
fi