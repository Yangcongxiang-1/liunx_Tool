"""
飞书机器人配置管理
====================
从 .env 文件加载飞书应用配置和运行时参数。
"""

import os
from pathlib import Path
from dotenv import load_dotenv

_env_path = Path(__file__).parent / ".env"
if _env_path.exists():
    load_dotenv(_env_path)


class Config:
    """飞书机器人配置 — 所有配置项通过环境变量或 .env 文件设置。"""

    # ── 飞书应用凭证 ──────────────────────────────────────────────────────
    APP_ID: str = os.getenv("FEISHU_APP_ID", "")
    """飞书应用的 App ID，在开发者后台获取。"""

    APP_SECRET: str = os.getenv("FEISHU_APP_SECRET", "")
    """飞书应用的 App Secret，在开发者后台获取。"""

    # ── AI 行为控制 ───────────────────────────────────────────────────────
    AI_RESPONSE_ENABLED: bool = os.getenv("AI_RESPONSE_ENABLED", "true").lower() in (
        "true", "1", "yes",
    )
    """是否开启 AI 自动回复。关闭后机器人仅接收消息但不自动回复。"""

    BOT_OPEN_ID: str = os.getenv("BOT_OPEN_ID", "")
    """机器人自己的 open_id，用于过滤自己发出的消息，防止循环。
    首次启动日志中可找到 open_id=ou_xxx...，填入即可。"""

    # ── 运行时参数（可调整）─────────────────────────────────────────────────
    POLL_INTERVAL: float = float(os.getenv("POLL_INTERVAL", "1.5"))
    """inbox 队列轮询间隔（秒）。"""

    STABLE_WAIT: int = int(os.getenv("STABLE_WAIT", "5"))
    """AI 回复稳定检测等待时间（秒）。"""

    MSG_FRESH_SEC: int = int(os.getenv("MSG_FRESH_SEC", "30"))
    """消息时效过滤阈值（秒），超过此时间的消息丢弃。"""

    OPENCODE_PORT: int = int(os.getenv("OPENCODE_PORT", "4096"))
    """OpenCode Web 服务端口。"""

    # ── 飞书 API 端点 ────────────────────────────────────────────────────
    BASE_URL: str = "https://open.feishu.cn/open-apis"
    """飞书开放 API 基础地址。"""

    # ── Webhook 服务器（备选模式）────────────────────────────────────────────
    WEBHOOK_HOST: str = os.getenv("WEBHOOK_HOST", "0.0.0.0")
    """Webhook 服务器监听地址。"""

    WEBHOOK_PORT: int = int(os.getenv("WEBHOOK_PORT", "8080"))
    """Webhook 服务器监听端口。"""

    VERIFY_TOKEN: str = os.getenv("FEISHU_VERIFY_TOKEN", "")
    """飞书事件验证令牌。可选，用于增强 Webhook 安全性。"""

    # ── 文件路径 ───────────────────────────────────────────────────────────
    INBOX_FILE: str = "/tmp/feishu-inbox.json"
    """消息队列文件路径（供 feishu_bot → watch_feishu 传递消息）。"""

    CHAT_LOG: str = "/tmp/feishu-chat.log"
    """对话日志文件路径。"""

    @classmethod
    def validate(cls) -> list[str]:
        """验证必要配置是否完整。

        Returns:
            缺失配置项的列表。空列表表示配置完整。
        """
        missing: list[str] = []
        if not cls.APP_ID:
            missing.append("FEISHU_APP_ID")
        if not cls.APP_SECRET:
            missing.append("FEISHU_APP_SECRET")
        return missing

    @classmethod
    def is_valid(cls) -> bool:
        return len(cls.validate()) == 0

    @classmethod
    def summary(cls) -> dict:
        """返回配置摘要（隐藏敏感信息）。"""
        return {
            "app_id": cls.APP_ID[:8] + "***" if cls.APP_ID else "(未设置)",
            "has_secret": bool(cls.APP_SECRET),
            "ai_response_enabled": cls.AI_RESPONSE_ENABLED,
            "bot_open_id": cls.BOT_OPEN_ID[:8] + "***" if cls.BOT_OPEN_ID else "(未设置)",
            "poll_interval": cls.POLL_INTERVAL,
            "stable_wait": cls.STABLE_WAIT,
            "msg_fresh_sec": cls.MSG_FRESH_SEC,
            "opencode_port": cls.OPENCODE_PORT,
        }
