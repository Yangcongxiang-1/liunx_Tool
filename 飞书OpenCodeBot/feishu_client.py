"""
飞书 API 客户端
===============
封装飞书开放平台核心 API，提供：
- 自动管理 tenant_access_token（获取 + 缓存 + 自动刷新）
- 发送消息（文本、富文本、卡片）
- 查询机器人 / 用户信息
- 命令行模式

用法（Python）：
    from feishu_client import FeishuClient
    client = FeishuClient()
    result = client.send_text("ou_xxx", "你好！")

用法（命令行）：
    python feishu_client.py --action send --to "ou_xxx" --type text --content "你好"
    python feishu_client.py --action status
"""

import json
import sys
import time
import argparse
from pathlib import Path
from typing import Any

import requests

sys.path.insert(0, str(Path(__file__).parent.resolve()))
from config import Config


class FeishuClient:
    """飞书 API 客户端 — 自动管理 token，统一返回格式 {"ok": bool, "data": Any, "error": str}。"""

    def __init__(self, app_id: str | None = None, app_secret: str | None = None):
        self._app_id = app_id or Config.APP_ID
        self._app_secret = app_secret or Config.APP_SECRET
        self._base_url = Config.BASE_URL

        self._token: str | None = None
        self._token_expire_at: float = 0.0

        self._session = requests.Session()
        self._session.headers.update({"Content-Type": "application/json"})

        if not self._app_id or not self._app_secret:
            raise ValueError("缺少飞书凭证：请在 .env 中设置 FEISHU_APP_ID 和 FEISHU_APP_SECRET")

    # ── Token 管理 ──────────────────────────────────────────────────────────

    def _get_tenant_access_token(self) -> str:
        """获取 tenant_access_token（自动缓存，预留 5 分钟刷新缓冲）。"""
        if self._token and time.time() < self._token_expire_at - 300:
            return self._token

        resp = self._session.post(
            f"{self._base_url}/auth/v3/tenant_access_token/internal",
            json={"app_id": self._app_id, "app_secret": self._app_secret},
            timeout=10,
        )
        data = resp.json()

        if data.get("code") != 0 or "tenant_access_token" not in data:
            raise RuntimeError(
                f"获取 tenant_access_token 失败: {data.get('msg', '未知错误')} "
                f"(code={data.get('code')})"
            )

        self._token = data["tenant_access_token"]
        self._token_expire_at = time.time() + data.get("expire", 7200)
        return self._token

    @property
    def _headers(self) -> dict:
        return {
            "Authorization": f"Bearer {self._get_tenant_access_token()}",
            "Content-Type": "application/json",
        }

    # ── HTTP 请求 ────────────────────────────────────────────────────────────

    def _post(self, path: str, payload: dict | None = None) -> dict:
        url = f"{self._base_url}{path}"
        return self._session.post(url, headers=self._headers, json=payload or {}, timeout=15).json()

    def _get(self, path: str, params: dict | None = None) -> dict:
        url = f"{self._base_url}{path}"
        return self._session.get(url, headers=self._headers, params=params or {}, timeout=15).json()

    # ── 消息发送 ─────────────────────────────────────────────────────────────

    def send_text(self, receive_id: str, content: str, receive_id_type: str = "open_id") -> dict:
        """发送文本消息。返回 {"ok": True, "data": message_id} 或 {"ok": False, "error": ...}"""
        result = self._post(
            f"/im/v1/messages?receive_id_type={receive_id_type}",
            {
                "receive_id": receive_id,
                "msg_type": "text",
                "content": json.dumps({"text": content}),
            },
        )
        if result.get("code") == 0:
            return {"ok": True, "data": result.get("data", {}).get("message_id", "")}
        return {"ok": False, "error": result.get("msg", "发送失败")}

    def send_rich_text(
        self, receive_id: str, content: str, title: str = "", receive_id_type: str = "open_id"
    ) -> dict:
        """发送富文本消息（支持 \\n 换行）。"""
        paragraphs = [
            [{"tag": "text", "text": line.strip()}]
            for line in content.strip().split("\n")
            if line.strip()
        ]
        post_content = {"zh_cn": {"title": title or "消息", "content": paragraphs}}
        result = self._post(
            f"/im/v1/messages?receive_id_type={receive_id_type}",
            {"receive_id": receive_id, "msg_type": "post", "content": json.dumps(post_content)},
        )
        if result.get("code") == 0:
            return {"ok": True, "data": result.get("data", {}).get("message_id", "")}
        return {"ok": False, "error": result.get("msg", "发送失败")}

    def send_card(
        self,
        receive_id: str,
        header_title: str,
        elements: list[dict],
        receive_id_type: str = "open_id",
    ) -> dict:
        """发送卡片消息。elements 参考飞书卡片 JSON 格式。"""
        card_content = {
            "config": {"wide_screen_mode": True},
            "header": {"title": {"tag": "plain_text", "content": header_title}, "template": "blue"},
            "elements": elements,
        }
        result = self._post(
            f"/im/v1/messages?receive_id_type={receive_id_type}",
            {"receive_id": receive_id, "msg_type": "interactive", "content": json.dumps(card_content)},
        )
        if result.get("code") == 0:
            return {"ok": True, "data": result.get("data", {}).get("message_id", "")}
        return {"ok": False, "error": result.get("msg", "发送失败")}

    # ── 信息查询 ─────────────────────────────────────────────────────────────

    def get_bot_info(self) -> dict:
        """获取机器人自身信息。"""
        result = self._get("/im/v1/bots/info")
        if result.get("code") == 0:
            return {"ok": True, "data": result.get("data", {})}
        return {"ok": False, "error": result.get("msg", "查询失败")}

    def get_user_info(self, user_id: str, user_id_type: str = "open_id") -> dict:
        """获取飞书用户信息。"""
        result = self._get("/contact/v3/users/batch_get_id", params={user_id_type: user_id})
        if result.get("code") == 0:
            return {"ok": True, "data": result.get("data", {})}
        return {"ok": False, "error": result.get("msg", "查询失败")}

    def status_check(self) -> dict:
        """全面检查机器人连通性：Token 获取 + 机器人信息查询。"""
        try:
            self._get_tenant_access_token()
        except RuntimeError as e:
            return {"ok": False, "error": str(e)}
        return self.get_bot_info()

    # ── 工具方法 ─────────────────────────────────────────────────────────────

    @staticmethod
    def build_simple_card(title: str, content: str, button_text: str | None = None, button_url: str | None = None) -> list[dict]:
        """构建简单消息卡片元素列表。"""
        elements: list[dict] = [{"tag": "markdown", "content": content}]
        if button_text and button_url:
            elements.append({
                "tag": "action",
                "actions": [{"tag": "button", "text": {"tag": "plain_text", "content": button_text}, "type": "default", "url": button_url}],
            })
        return elements


# ── 命令行入口 ──────────────────────────────────────────────────────────────


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="飞书机器人客户端 — 发送消息、查询状态")
    parser.add_argument("--action", choices=["send", "status", "info"], default="status", help="操作类型")
    parser.add_argument("--to", help="接收方 ID（open_id / chat_id）")
    parser.add_argument("--type", choices=["text", "rich_text", "card"], default="text", help="消息类型")
    parser.add_argument("--title", default="", help="消息标题")
    parser.add_argument("--content", default="", help="消息内容")
    parser.add_argument("--id-type", default="open_id", choices=["open_id", "union_id", "user_id", "chat_id"], help="接收方 ID 类型")
    return parser.parse_args()


def main():
    args = _parse_args()
    missing = Config.validate()
    if missing:
        print(f"❌ 配置缺失: {', '.join(missing)}")
        print("   请创建 .env 文件并设置飞书应用凭证。")
        sys.exit(1)

    try:
        client = FeishuClient()
    except ValueError as e:
        print(f"❌ {e}")
        sys.exit(1)

    if args.action == "status":
        result = client.status_check()
        if result.get("ok"):
            info = result["data"]
            print(f"✅ 机器人状态正常")
            print(f"   名称: {info.get('app_name', '未知')}")
            print(f"   App ID: {info.get('app_id', '未知')}")
        else:
            print(f"❌ 状态异常: {result.get('error')}")

    elif args.action == "info":
        result = client.get_bot_info()
        if result.get("ok"):
            print(json.dumps(result["data"], ensure_ascii=False, indent=2))
        else:
            print(f"❌ 查询失败: {result.get('error')}")

    elif args.action == "send":
        if not args.to:
            print("❌ 请指定接收方 (--to)"); sys.exit(1)
        if not args.content and args.type != "card":
            print("❌ 请指定消息内容 (--content)"); sys.exit(1)

        if args.type == "text":
            result = client.send_text(args.to, args.content, args.id_type)
        elif args.type == "rich_text":
            result = client.send_rich_text(args.to, args.content, args.title, args.id_type)
        elif args.type == "card":
            elements = FeishuClient.build_simple_card(args.title or "通知", args.content)
            result = client.send_card(args.to, args.title or "通知", elements, args.id_type)
        else:
            result = {"ok": False, "error": f"不支持的消息类型: {args.type}"}

        if result.get("ok"):
            print(f"✅ 消息发送成功 (message_id: {result['data']})")
        else:
            print(f"❌ 消息发送失败: {result.get('error')}")


if __name__ == "__main__":
    main()
