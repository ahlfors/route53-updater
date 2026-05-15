FROM alpine:3.20

LABEL maintainer="DevOps Team"
LABEL description="AWS Route53 Auto-Update with Feishu Notification"

# 安装运行依赖 + Python（用于 pip 安装 AWS CLI）
RUN apk add --no-cache \
    bash \
    curl \
    jq \
    tzdata \
    python3 \
    py3-pip \
    && rm -rf /var/cache/apk/*

# 通过 pip 安装 AWS CLI（纯 Python，支持所有架构）
RUN pip3 install --no-cache-dir --break-system-packages awscli

# 验证安装
RUN aws --version

# 设置默认时区
ENV TZ=Asia/Shanghai

# 创建工作目录
RUN mkdir -p /app/scripts /app/logs /app/crontab /app/state

# 复制脚本
COPY scripts/update-aws-route53.sh       /app/scripts/
COPY scripts/update-aws-route53-daemon.sh /app/scripts/
COPY scripts/entrypoint.sh               /app/scripts/
COPY crontab/route53-cron                /app/crontab/

# 设置执行权限
RUN chmod +x /app/scripts/*.sh

WORKDIR /app

ENTRYPOINT ["/app/scripts/entrypoint.sh"]