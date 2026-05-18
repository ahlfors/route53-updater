#!/usr/bin/env python3
"""
轻量 Webhook HTTP Server
接收 POST 请求，验证 Token，将 IP 写入缓存文件
"""

import os
import sys
import json
import re
from http.server import HTTPServer, BaseHTTPRequestHandler
from datetime import datetime

WEBHOOK_PORT = int(os.environ.get("WEBHOOK_PORT", "9090"))
WEBHOOK_TOKEN = os.environ.get("WEBHOOK_TOKEN", "")
IP_CACHE_FILE = os.environ.get("IP_CACHE_FILE", "/app/data/new_public_ip.txt")
LOG_FILE = "/app/logs/webhook.log"

IP_PATTERN = re.compile(r"^(\d{1,3}\.){3}\d{1,3}$")

def log(msg):
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{ts}] [WEBHOOK] {msg}"
    print(line, flush=True)
    try:
        with open(LOG_FILE, "a") as f:
            f.write(line + "\n")
    except Exception:
        pass

class WebhookHandler(BaseHTTPRequestHandler):
    """处理 HTTP 请求"""

    def log_message(self, format, *args):
        """覆盖默认日志，写入自定义日志"""
        log(f"{self.address_string()} - {format % args}")

    def _send_json(self, code, body):
        payload = json.dumps(body).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(payload)

    # ---------- GET /health ----------
    def do_GET(self):
        if self.path == "/health":
            self._send_json(200, {
                "status": "ok",
                "time": datetime.now().isoformat(),
            })
        else:
            self._send_json(404, {"error": "not found"})

    # ---------- POST / ----------
    def do_POST(self):
        # Token 验证
        auth = self.headers.get("Authorization", "")
        expected = f"Bearer {WEBHOOK_TOKEN}"
        if auth != expected:
            log(f"Unauthorized request from {self.address_string()}")
            self._send_json(401, {"error": "unauthorized"})
            return

        # 读取 Body
        content_length = int(self.headers.get("Content-Length", 0))
        if content_length == 0:
            self._send_json(400, {"error": "empty body"})
            return

        body = self.rfile.read(content_length).decode("utf-8", errors="replace")

        # 解析 IP
        try:
            data = json.loads(body)
            new_ip = data.get("ip", "").strip()
        except json.JSONDecodeError:
            # 兜底：直接从 body 中提取 IP
            match = re.search(r"(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})", body)
            new_ip = match.group(1) if match else ""

        if not new_ip or not IP_PATTERN.match(new_ip):
            self._send_json(400, {"error": "invalid or missing ip"})
            return

        # 写入 IP 缓存文件
        try:
            os.makedirs(os.path.dirname(IP_CACHE_FILE), exist_ok=True)
            with open(IP_CACHE_FILE, "w") as f:
                f.write(new_ip + "\n")
            log(f"IP written: {new_ip} -> {IP_CACHE_FILE}")
            self._send_json(200, {"status": "accepted", "ip": new_ip})
        except Exception as e:
            log(f"Failed to write IP file: {e}")
            self._send_json(500, {"error": f"write failed: {str(e)}"})

def main():
    if not WEBHOOK_TOKEN:
        log("FATAL: WEBHOOK_TOKEN is not set!")
        sys.exit(1)

    log(f"Starting webhook server on port {WEBHOOK_PORT}")
    log(f"IP cache file: {IP_CACHE_FILE}")

    server = HTTPServer(("0.0.0.0", WEBHOOK_PORT), WebhookHandler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        log("Shutting down...")
        server.server_close()

if __name__ == "__main__":
    main()