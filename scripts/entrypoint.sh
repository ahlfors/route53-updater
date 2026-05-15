#!/bin/bash
###############################################################################
# 容器入口脚本
# 1. 校验环境变量
# 2. 配置 AWS CLI
# 3. 导出环境变量供 cron 使用
# 4. 启动 Webhook 监听（后台）
# 5. 启动 crond（前台保活）
###############################################################################

set -e

echo "============================================="
echo "  AWS Route53 Auto-Update Container"
echo "  Starting at: $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "============================================="

# ---------- 校验必要环境变量 ----------
REQUIRED_VARS=("FEISHU_WEBHOOK_TOKEN" "AWS_ACCESS_KEY_ID" "AWS_SECRET_ACCESS_KEY" "AWS_DEFAULT_REGION" "ZONE_ID" "RECORD_NAMES" "WEBHOOK_TOKEN")
for var in "${REQUIRED_VARS[@]}"; do
  if [ -z "${!var}" ]; then
    echo "[FATAL] Required environment variable '${var}' is not set!"
    exit 1
  fi
done

echo "[INFO] Target Name       : ${TARGET_NAME:-N/A}"
echo "[INFO] AWS Region        : ${AWS_DEFAULT_REGION}"
echo "[INFO] Zone ID           : ${ZONE_ID}"
echo "[INFO] Record Names      : ${RECORD_NAMES}"
echo "[INFO] IP Cache File     : ${IP_CACHE_FILE:-/app/data/new_public_ip.txt}"
echo "[INFO] Cron Schedule     : ${CHECK_CRON_SCHEDULE:-*/1 * * * *}"
echo "[INFO] Webhook Port      : ${WEBHOOK_PORT:-9090}"
echo "[INFO] Timezone          : ${TZ:-Asia/Shanghai}"
echo ""

# ---------- 配置 AWS CLI ----------
echo "[INFO] Configuring AWS CLI..."
aws configure set aws_access_key_id "${AWS_ACCESS_KEY_ID}"
aws configure set aws_secret_access_key "${AWS_SECRET_ACCESS_KEY}"
aws configure set default.region "${AWS_DEFAULT_REGION}"
aws configure set output json
echo "[INFO] AWS CLI configured successfully"

if aws sts get-caller-identity > /dev/null 2>&1; then
  echo "[INFO] AWS credentials verified ✅"
else
  echo "[WARN] AWS credentials verification failed (may still work for Route53)"
fi

# ---------- 导出环境变量 ----------
ENV_FILE="/app/state/container.env"
cat > "$ENV_FILE" <<EOF
export FEISHU_WEBHOOK_TOKEN="${FEISHU_WEBHOOK_TOKEN}"
export TARGET_NAME="${TARGET_NAME}"
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION}"
export ZONE_ID="${ZONE_ID}"
export RECORD_NAMES="${RECORD_NAMES}"
export IP_CACHE_FILE="${IP_CACHE_FILE:-/app/data/new_public_ip.txt}"
export WEBHOOK_TOKEN="${WEBHOOK_TOKEN}"
export WEBHOOK_PORT="${WEBHOOK_PORT:-9090}"
export TZ="${TZ:-Asia/Shanghai}"
export HOME="/root"
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
EOF
chmod 600 "$ENV_FILE"

# ---------- 初始化目录 ----------
mkdir -p /app/logs /app/data
touch /app/logs/route53.log /app/logs/webhook.log

# ---------- 动态生成 crontab ----------
CRON_SCHEDULE="${CHECK_CRON_SCHEDULE:-*/1 * * * *}"
CRON_FILE="/etc/crontabs/root"

cat > "$CRON_FILE" <<EOF
# AWS Route53 Auto-Update Daemon (Asia/Shanghai)
${CRON_SCHEDULE} /bin/bash -c 'source /app/state/container.env && /app/scripts/update-aws-route53-daemon.sh >> /app/logs/route53.log 2>&1'
EOF

echo "[INFO] Crontab installed:"
cat "$CRON_FILE"
echo ""

# ---------- 后台启动 Webhook 监听 ----------
echo "[INFO] Starting webhook listener on port ${WEBHOOK_PORT:-9090}..."
/bin/bash /app/scripts/webhook.sh >> /app/logs/webhook.log 2>&1 &
WEBHOOK_PID=$!
echo "[INFO] Webhook started (PID: ${WEBHOOK_PID})"

# ---------- 前台运行 crond ----------
echo "[INFO] Starting cron daemon..."
echo "============================================="
exec crond -f -l 2