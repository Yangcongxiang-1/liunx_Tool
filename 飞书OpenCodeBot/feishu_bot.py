"""
飞书机器人 — WebSocket 长连接消息接收网关
=========================================
使用 lark-oapi 的 FeishuChannel 建立 WebSocket 长连接，
接收飞书消息并写入 inbox 队列供 AI 处理。

无需公网 IP，仅需出网能力。

启动方式：
    python feishu_bot.py
"""

import json
import sys
import time
import asyncio
import signal
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).parent.resolve()))
from config import Config
from feishu_client import FeishuClient

try:
    import lark_oapi as lark
    from lark_oapi.channel import FeishuChannel
except ImportError:
    print("❌ 缺少 lark-oapi 依赖，请运行: pip install lark-oapi")
    sys.exit(1)


# ── 消息队列 ────────────────────────────────────────────────────────────────

_message_queue: list[dict] = []


def _save_inbox() -> None:
    """将消息队列保存到文件，供 watch_feishu（本进程外）读取。"""
    try:
        with open(Config.INBOX_FILE, "w", encoding="utf-8") as f:
            json.dump(_message_queue[-50:], f, ensure_ascii=False, indent=2)
    except Exception as e:
        print(f"   ⚠️ 保存消息文件失败: {e}")


# ── 事件处理 ────────────────────────────────────────────────────────────────

_shutdown = False
_feishu_client: FeishuClient | None = None


async def on_message(msg: Any) -> None:
    """处理收到的飞书消息。"""
    global _feishu_client

    sender_id = getattr(msg, "sender_id", "") or ""
    message_id = getattr(msg, "message_id", "") or ""
    chat_id = getattr(msg, "chat_id", "") or ""
    chat_type = getattr(msg, "chat_type", "p2p")
    text = getattr(msg, "content_text", "") or ""

    print(f"\n📩 收到飞书消息:")
    print(f"   发送者: {sender_id}")
    print(f"   消息ID: {message_id}")
    print(f"   类型:   {chat_type}")
    print(f"   内容:   {text[:200]}")

    # 过滤机器人自己的消息，防止循环
    if Config.BOT_OPEN_ID and sender_id == Config.BOT_OPEN_ID:
        print(f"   ↳ 跳过机器人自己的消息")
        return

    # 加入消息队列（含时间戳）
    _message_queue.append({
        "sender_id": sender_id,
        "message_id": message_id,
        "chat_id": chat_id,
        "chat_type": chat_type,
        "text": text,
        "timestamp": int(time.time()),
    })
    _save_inbox()

    # 私聊自动回复确认
    if Config.AI_RESPONSE_ENABLED and chat_type == "p2p" and _feishu_client:
        try:
            _feishu_client.send_text(sender_id, "已收到你的消息 ✅ 我会尽快处理。")
            print(f"   ↳ 已发送自动确认回复")
        except Exception as e:
            print(f"   ⚠️ 自动回复失败: {e}")


async def on_error(err: Any) -> None:
    print(f"\n❌ 飞书通道错误: {err}")


# ── 优雅关闭 ────────────────────────────────────────────────────────────────

def _signal_handler(sig, frame) -> None:
    global _shutdown
    if _shutdown:
        return
    _shutdown = True
    print("\n\n🛑 收到关闭信号，正在停止机器人...")


# ── 主入口 ──────────────────────────────────────────────────────────────────

def main():
    global _feishu_client

    missing = Config.validate()
    if missing:
        print(f"❌ 配置缺失: {', '.join(missing)}")
        print(f"   请编辑 {Path(__file__).parent / '.env'} 文件设置 App ID 和 App Secret")
        sys.exit(1)

    try:
        _feishu_client = FeishuClient()
        print(f"✅ Feishu API 客户端初始化成功 (App ID: {Config.APP_ID[:12]}...)")
    except ValueError as e:
        print(f"❌ Feishu API 客户端初始化失败: {e}")
        sys.exit(1)

    signal.signal(signal.SIGINT, _signal_handler)
    signal.signal(signal.SIGTERM, _signal_handler)

    print(f"\n{'='*50}")
    print(f"  飞书机器人启动中...")
    print(f"  App ID:  {Config.APP_ID[:12]}...")
    print(f"  模式:    WebSocket 长连接 (FeishuChannel)")
    print(f"{'='*50}\n")

    channel = FeishuChannel(
        app_id=Config.APP_ID,
        app_secret=Config.APP_SECRET,
        log_level=lark.LogLevel.INFO,
    )
    channel.on("message", on_message)
    channel.on("error", on_error)

    try:
        asyncio.run(channel.connect())
    except KeyboardInterrupt:
        print("\n\n👋 机器人已停止")
    except Exception as e:
        print(f"\n❌ 运行异常: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
