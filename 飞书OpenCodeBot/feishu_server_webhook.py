"""
飞书 Webhook 回调服务器（备选模式）
===================================
当 WebSocket 长连接不可用时，使用此 Webhook 模式接收飞书事件推送。

启动方式：
    python feishu_server_webhook.py
    python feishu_server_webhook.py --port 8080 --debug
"""

import json
import sys
import argparse
from pathlib import Path
from typing import Any, Callable

sys.path.insert(0, str(Path(__file__).parent.resolve()))
from config import Config
from feishu_client import FeishuClient

try:
    from flask import Flask, request, jsonify
except ImportError:
    print("❌ 缺少 Flask 依赖，请运行: pip install flask")
    sys.exit(1)


# ── 事件处理器注册表 ──────────────────────────────────────────────────────

_event_handlers: dict[str, list[Callable[[dict], dict | None]]] = {}


def on_event(event_type: str):
    """装饰器：注册飞书事件处理器。"""
    def decorator(func: Callable[[dict], dict | None]):
        _event_handlers.setdefault(event_type, []).append(func)
        return func
    return decorator


# ── Flask 应用 ──────────────────────────────────────────────────────────────

app = Flask(__name__)


@app.route("/webhook/event", methods=["POST"])
def handle_event():
    """飞书事件回调主入口 — 支持 URL 验证和事件分发。"""
    data = request.get_json(silent=True)
    if not data:
        return jsonify({"error": "无效的请求体"}), 400

    # URL 验证（飞书首次配置时校验）
    if "challenge" in data:
        if Config.VERIFY_TOKEN and data.get("token") != Config.VERIFY_TOKEN:
            return jsonify({"error": "token 验证失败"}), 403
        return jsonify({"challenge": data["challenge"]})

    # 事件回调
    event_type = data.get("header", {}).get("event_type", "") or data.get("event_type", "")
    event_body = data.get("event", {}) or data

    # 分发到已注册的处理器
    responses = []
    for handler in _event_handlers.get(event_type, []):
        try:
            result = handler(event_body)
            if result:
                responses.append(result)
        except Exception as e:
            print(f"事件处理器 {handler.__name__} 异常: {e}")

    return jsonify({"code": 0, "msg": "ok", "data": responses})


@app.route("/webhook/health", methods=["GET"])
def health_check():
    return jsonify({
        "status": "ok",
        "app_id": Config.APP_ID[:8] + "***" if Config.APP_ID else None,
        "ai_enabled": Config.AI_RESPONSE_ENABLED,
        "handlers": list(_event_handlers.keys()),
    })


@app.route("/webhook/status", methods=["GET"])
def status_check():
    if not Config.is_valid():
        return jsonify({"status": "error", "message": "飞书凭证未配置", "missing": Config.validate()})
    try:
        result = FeishuClient().status_check()
        if result.get("ok"):
            return jsonify({"status": "ok", "bot": result.get("data", {}), "config": Config.summary()})
        return jsonify({"status": "error", "message": result.get("error")})
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)})


# ── 默认事件处理器 ──────────────────────────────────────────────────────────


@on_event("im.message.receive_v1")
def handle_message(event: dict) -> dict | None:
    """处理收到的消息事件。"""
    sender = event.get("sender", {})
    message = event.get("message", {})

    sender_id = sender.get("sender_id", {}).get("open_id", "")
    message_id = message.get("message_id", "")
    chat_type = message.get("chat_type", "p2p")
    msg_type = message.get("message_type", "text")
    chat_id = message.get("chat_id", "")

    # 解析消息内容
    raw = message.get("content", "{}")
    try:
        content = json.loads(raw) if isinstance(raw, str) else raw
    except json.JSONDecodeError:
        content = {"text": raw}
    text = content.get("text", "")

    print(f"📩 Webhook 消息: from={sender_id}, type={msg_type}, chat={chat_type}, text={text[:100]}")

    # AI 自动回复
    if Config.AI_RESPONSE_ENABLED and chat_type == "p2p":
        try:
            FeishuClient().send_text(sender_id, "已收到你的消息 ✅ 我会尽快处理。")
            print(f"   ↳ 已发送自动确认回复")
        except Exception as e:
            print(f"   ⚠️ 自动回复失败: {e}")

    return {"handled": True, "sender_id": sender_id, "message_id": message_id, "text": text}


# ── 启动入口 ────────────────────────────────────────────────────────────────


def main():
    parser = argparse.ArgumentParser(description="飞书机器人 Webhook 服务器（备选模式）")
    parser.add_argument("--host", default=Config.WEBHOOK_HOST, help="监听地址")
    parser.add_argument("--port", type=int, default=Config.WEBHOOK_PORT, help="监听端口")
    parser.add_argument("--debug", action="store_true", default=False, help="调试模式")
    args = parser.parse_args()

    missing = Config.validate()
    if missing:
        print(f"⚠️ 配置缺失: {', '.join(missing)}")
        print("   服务器将在配置不全的情况下启动，但部分功能不可用。")

    print(f"🚀 飞书 Webhook 服务器启动: http://{args.host}:{args.port}")
    print(f"   事件回调 URL: http://{args.host}:{args.port}/webhook/event")
    print(f"   健康检查: http://{args.host}:{args.port}/webhook/health")
    print(f"   状态检查: http://{args.host}:{args.port}/webhook/status")

    app.run(host=args.host, port=args.port, debug=args.debug)


if __name__ == "__main__":
    main()
