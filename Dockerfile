FROM alpine:3.20

LABEL maintainer="DevOps Team"
LABEL description="AWS Route53 Auto-Update with Feishu Notification"

RUN apk add --no-cache \
    bash \
    curl \
    jq \
    tzdata \
    python3 \
    py3-pip \
    nmap-ncat \
    && rm -rf /var/cache/apk/*

RUN pip3 install --no-cache-dir --break-system-packages awscli

RUN aws --version

ENV TZ=Asia/Shanghai

RUN mkdir -p /app/scripts /app/logs /app/crontab /app/state /app/data

COPY scripts/update-aws-route53.sh       /app/scripts/
COPY scripts/update-aws-route53-daemon.sh /app/scripts/
COPY scripts/webhook.sh                  /app/scripts/
COPY scripts/webhook-handler.sh          /app/scripts/
COPY scripts/entrypoint.sh               /app/scripts/
COPY crontab/route53-cron                /app/crontab/

RUN chmod +x /app/scripts/*.sh

WORKDIR /app

EXPOSE 9090

ENTRYPOINT ["/app/scripts/entrypoint.sh"]