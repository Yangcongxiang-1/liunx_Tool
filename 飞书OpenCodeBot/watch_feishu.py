"""
飞书消息监控 — 自动通过 OpenCode AI 处理并回复
=============================================
工作流程：
    feishu_bot 接收飞书消息 → /tmp/feishu-inbox.json
    → watch_feishu 轮询检测 → opencode run --attach 发送给 AI
    → AI 处理（保留全部 skill 能力）
    → 轮询 SQLite 等待回复（稳定检测 5s）
    → feishu_client 发送回复到飞书

用法：
    python watch_feishu.py               # 启动监控
    python watch_feishu.py --history      # 查看对话历史
    python watch_feishu.py --init-session # 初始化飞书专用会话
"""

import json
import os
import sys
import time
import signal
import sqlite3
import subprocess
import re
from pathlib import Path
from datetime import datetime
from typing import NoReturn

sys.path.insert(0, str(Path(__file__).parent.resolve()))
from feishu_client import FeishuClient
from config import Config

# ── 常量 ─────────────────────────────────────────────────────────────────

OPENCODE_WEB_URL = f"http://127.0.0.1:{Config.OPENCODE_PORT}"
SESSION_FILE = os.path.expanduser("~/.config/opencode/skills/feishu-bot/.feishu_session_id")
OPCODE_DB = os.path.expanduser("~/.local/share/opencode/opencode.db")

# ── 状态 ─────────────────────────────────────────────────────────────────

_running = True
_processed_ids: set[str] = set()
_client: FeishuClient | None = None
_feishu_session_id: str | None = None


# ── 日志 ─────────────────────────────────────────────────────────────────

def log(msg: str) -> None:
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{ts}] {msg}", flush=True)


def append_chat_log(entry: dict) -> None:
    try:
        with open(Config.CHAT_LOG, "a", encoding="utf-8") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    except Exception as e:
        log(f"⚠️ 写入对话日志失败: {e}")


# ── 会话管理 ─────────────────────────────────────────────────────────────

def get_session_id() -> str | None:
    """从文件读取保存的飞书会话 ID。"""
    if os.path.exists(SESSION_FILE):
        try:
            sid = Path(SESSION_FILE).read_text().strip()
            if sid:
                return sid
        except Exception:
            pass
    return None


def save_session_id(session_id: str) -> None:
    """保存飞书会话 ID 到文件。"""
    try:
        os.makedirs(os.path.dirname(SESSION_FILE), exist_ok=True)
        Path(SESSION_FILE).write_text(session_id.strip())
        log(f"✅ 已保存飞书会话 ID: {session_id[:20]}...")
    except Exception as e:
        log(f"⚠️ 保存会话 ID 失败: {e}")


def create_feishu_session() -> str | None:
    """创建新的飞书专用会话，返回会话 ID。"""
    log("🔄 正在创建飞书专用会话...")
    try:
        result = subprocess.run(
            ["opencode", "run", "--attach", OPENCODE_WEB_URL, "--title", "飞书消息处理", "--format", "json",
             "初始化飞书处理会话"],
            capture_output=True, text=True, timeout=30,
        )
        for line in result.stdout.splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                event = json.loads(line)
                sid = event.get("sessionID", "")
                if sid and sid.startswith("ses_"):
                    save_session_id(sid)
                    return sid
            except json.JSONDecodeError:
                continue
        for line in result.stderr.splitlines():
            m = re.search(r'(ses_[a-zA-Z0-9]+)', line)
            if m:
                sid = m.group(1)
                save_session_id(sid)
                return sid
        log("⚠️ 无法从输出中提取会话 ID")
        return None
    except subprocess.TimeoutExpired:
        log("⚠️ 创建会话超时")
        return None
    except FileNotFoundError:
        log("❌ 找不到 opencode 命令，请确认 opencode 已安装")
        return None
    except Exception as e:
        log(f"❌ 创建会话失败: {e}")
        return None


def ensure_session() -> str | None:
    """确保飞书会话存在，返回会话 ID。"""
    global _feishu_session_id
    sid = get_session_id()
    if sid:
        _feishu_session_id = sid
        return sid

    sid = create_feishu_session()
    if sid:
        _feishu_session_id = sid
        return sid

    # 从已有会话列表中找飞书相关会话
    try:
        result = subprocess.run(["opencode", "session", "list"], capture_output=True, text=True, timeout=10)
        for line in result.stdout.splitlines():
            if "飞书" in line:
                parts = line.split()
                if parts and parts[0].startswith("ses_"):
                    save_session_id(parts[0])
                    _feishu_session_id = parts[0]
                    return parts[0]
    except Exception:
        pass
    return None


# ── AI 处理 ──────────────────────────────────────────────────────────────


def _get_latest_ai_text(session_id: str, since_time: int = 0) -> tuple[int, str] | None:
    """获取 AI 最新文本回复 (time_updated, text)，只取 AI 生成的有 time.start 的 type=text 记录。"""
    try:
        conn = sqlite3.connect(OPCODE_DB)
        if since_time > 0:
            rows = conn.execute(
                """SELECT time_updated, data FROM part
                   WHERE session_id = ?
                     AND json_extract(data, '$.type') = 'text'
                     AND json_extract(data, '$.time.start') IS NOT NULL
                     AND time_updated > ?
                   ORDER BY time_updated DESC LIMIT 1""",
                (session_id, since_time),
            ).fetchall()
        else:
            rows = conn.execute(
                """SELECT time_updated, data FROM part
                   WHERE session_id = ?
                     AND json_extract(data, '$.type') = 'text'
                     AND json_extract(data, '$.time.start') IS NOT NULL
                   ORDER BY time_updated DESC LIMIT 1""",
                (session_id,),
            ).fetchall()
        conn.close()
        if rows:
            ts, data_str = rows[0]
            text = json.loads(data_str).get("text", "")
            if text:
                return (ts, text)
    except Exception:
        pass
    return None


def process_with_ai(text: str, sender_id: str, chat_id: str) -> str | None:
    """把飞书消息发给 AI，返回 AI 的完整文本回复。

    通过 opencode run --attach 发送消息到 Web 服务器的飞书专用会话，
    轮询数据库获取 AI 回复，等待 5 秒无变化才返回（稳定检测）。
    """
    session_id = _feishu_session_id
    if not session_id:
        log("⚠️ 没有飞书会话 ID，无法处理消息")
        return None

    # 记录当前数据库时间戳，只查之后新增的回复
    try:
        conn = sqlite3.connect(OPCODE_DB)
        before_max = conn.execute(
            "SELECT COALESCE(MAX(time_updated), 0) FROM part WHERE session_id = ?",
            (session_id,),
        ).fetchone()[0]
        conn.close()
    except Exception:
        before_max = 0

    log(f"   ↳ 发送给 AI 处理（时间戳基准: {before_max}）...")

    try:
        subprocess.run(
            ["opencode", "run", "--attach", OPENCODE_WEB_URL, "-c", "-s", session_id, f"[飞书消息] 用户说: {text}"],
            capture_output=True, timeout=30,
        )
    except FileNotFoundError:
        log("❌ 找不到 opencode 命令")
        return None
    except subprocess.TimeoutExpired:
        log("   ⚠️ 发送命令超时，继续等待 AI 处理...")
    except Exception as e:
        log(f"   ⚠️ 发送消息异常: {e}，继续等待 AI 处理...")

    # 轮询数据库等待 AI 回复（最长 120 秒），稳定检测 5 秒
    stable_text = None
    stable_time = 0

    for _ in range(120):
        result = _get_latest_ai_text(session_id, since_time=before_max)
        now = int(time.time())

        if result:
            ts, text_content = result
            if ts != stable_time:
                stable_text = text_content
                stable_time = ts
                log(f"   ↳ 检测到 AI 新回复（等待 {Config.STABLE_WAIT}s 确认稳定）...")
                time.sleep(1)
                continue
            else:
                elapsed = now - int(ts / 1000)
                if elapsed >= Config.STABLE_WAIT:
                    log(f"✅ AI 回复稳定（{elapsed}s 无变化）: {stable_text[:150]}")
                    return stable_text

        time.sleep(1)

    if stable_text:
        log(f"⚠️ AI 回复未完全稳定，返回最后内容: {stable_text[:150]}")
        return stable_text

    log("⚠️ AI 未在 120 秒内回复")
    return None


# ── 消息处理 ─────────────────────────────────────────────────────────────


def _extract_open_id(sender_id) -> str:
    """从 sender_id（可能是 dict 或字符串）中提取 open_id。"""
    if isinstance(sender_id, dict):
        return sender_id.get("open_id", "")
    return str(sender_id) if sender_id else ""


def handle_message(msg: dict) -> None:
    """处理单条飞书消息。"""
    global _client
    msg_id = msg.get("message_id", "")
    if not msg_id or msg_id in _processed_ids:
        return
    _processed_ids.add(msg_id)

    sender_id = _extract_open_id(msg.get("sender_id", ""))
    text = msg.get("text", "")
    chat_type = msg.get("chat_type", "p2p")
    chat_id = msg.get("chat_id", "")

    # 时效过滤：只处理 30 秒内的消息
    msg_time = msg.get("timestamp", 0)
    if msg_time and int(time.time()) - msg_time > Config.MSG_FRESH_SEC:
        log(f"⏭️ 跳过过期消息（>{Config.MSG_FRESH_SEC}s）: {text[:80]}")
        return

    log(f"📩 {'私聊' if chat_type == 'p2p' else '群聊'} {sender_id[-12:]}: {text[:200]}")

    append_chat_log({
        "time": datetime.now().isoformat(),
        "sender_id": sender_id,
        "message_id": msg_id,
        "chat_id": chat_id,
        "chat_type": chat_type,
        "text": text,
        "direction": "in",
    })

    if chat_type != "p2p":
        return  # 只处理私聊消息
    if not _client:
        log("⚠️ FeishuClient 未初始化，跳过回复")
        return

    reply = process_with_ai(text, sender_id, chat_id)
    if reply is None:
        reply = f"收到你的消息了 ✅ 我会尽快处理。消息内容：{text[:100]}"

    try:
        result = _client.send_text(sender_id, reply)
        if result.get("ok"):
            append_chat_log({
                "time": datetime.now().isoformat(),
                "sender_id": "bot",
                "text": reply,
                "direction": "out",
            })
            log(f"✅ 已回复飞书用户: {reply[:100]}")
        else:
            log(f"⚠️ 回复失败: {result.get('error')}")
    except Exception as e:
        log(f"⚠️ 回复异常: {e}")


# ── 轮询 ─────────────────────────────────────────────────────────────────


def poll_messages() -> None:
    """轮询检查新消息。"""
    if not Path(Config.INBOX_FILE).exists():
        return
    try:
        content = Path(Config.INBOX_FILE).read_text(encoding="utf-8").strip()
        if not content or content == "[]":
            return
        messages = json.loads(content)
    except (json.JSONDecodeError, OSError):
        return
    if not messages:
        return
    for msg in messages:
        handle_message(msg)
    try:
        Path(Config.INBOX_FILE).write_text("[]", encoding="utf-8")
    except OSError as e:
        log(f"⚠️ 清空消息文件失败: {e}")


# ── 信号处理 ─────────────────────────────────────────────────────────────


def signal_handler(sig, frame) -> None:
    global _running
    if not _running:
        return
    _running = False
    log(f"\n🛑 监控停止，共处理 {len(_processed_ids)} 条消息")


# ── 历史查看 ─────────────────────────────────────────────────────────────


def show_history(lines: int = 30) -> None:
    if not Path(Config.CHAT_LOG).exists():
        print("暂无对话记录。")
        return
    try:
        all_lines = Path(Config.CHAT_LOG).read_text(encoding="utf-8").splitlines()
        recent = all_lines[-lines:]
        print(f"\n📋 最近对话 ({len(recent)} 条):")
        print("-" * 60)
        for line in recent:
            entry = json.loads(line)
            who = "🤖" if entry.get("direction") == "out" else "👤"
            ts = entry.get("time", "")[11:19]
            txt = entry.get("text", "")
            print(f"{who} [{ts}] {txt[:150]}")
        print("-" * 60)
    except Exception as e:
        print(f"读取对话日志失败: {e}")


# ── 入口 ─────────────────────────────────────────────────────────────────


def main() -> NoReturn:
    global _client

    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    try:
        _client = FeishuClient()
    except ValueError as e:
        print(f"❌ {e}")
        sys.exit(1)

    print(f"\n{'='*50}")
    print(f"  飞书消息监控 (AI 处理模式)")
    print(f"  收到消息 → opencode AI 处理 → 回复飞书")
    print(f"  AI 保留全部 skill 插件能力")
    print(f"{'='*50}")

    sid = ensure_session()
    if sid:
        global _feishu_session_id
        _feishu_session_id = sid
        print(f"\n✅ 飞书会话: {sid}")
    else:
        print(f"\n⚠️ 未能获取飞书会话，AI 处理将不可用")
        print(f"   可稍后运行: python {__file__} --init-session")

    print(f"  按 Ctrl+C 停止\n")

    while _running:
        try:
            poll_messages()
            time.sleep(Config.POLL_INTERVAL)
        except KeyboardInterrupt:
            break
        except Exception as e:
            log(f"❌ 监控异常: {e}")
            time.sleep(Config.POLL_INTERVAL * 2)

    print(f"\n👋 监控停止")


def init_session_main() -> None:
    """仅初始化飞书会话（--init-session 模式）。"""
    sid = ensure_session()
    if sid:
        print(f"✅ 飞书会话就绪: {sid}")
        print(f"   保存在: {SESSION_FILE}")
    else:
        print("❌ 创建飞书会话失败")
        sys.exit(1)


if __name__ == "__main__":
    if len(sys.argv) > 1:
        arg = sys.argv[1]
        if arg in ("--history", "-h"):
            show_history()
        elif arg in ("--init-session", "-i"):
            init_session_main()
        else:
            print(f"未知参数: {arg}")
            print(f"用法: python {__file__} [--history | --init-session]")
            sys.exit(1)
    else:
        main()
