#!/usr/bin/env python3
"""
DSH 协议自检：在命令行完整复现 App 的网络行为。

用途：App 出问题时，先用本脚本确认服务端与协议是否正常，
      避免为每一处改动反复编译、安装、抓日志。

覆盖链路（与 entry/.../core/DshClient.ets 一一对应）：
  1. 认证      GET /?token=...        → 303 + Set-Cookie dsh-auth-*
  2. 列会话    POST /api/session/list
  3. 建会话    POST /api/session/create
  4. 发消息    POST /api/session/prompt
  5. 收流      WS  /api/remote.mux    → open frame {args:{request:...}}
  6. 收尾      POST /api/session/cancel（可选）

用法：
  python3 scripts/dsh-check.py --base https://yiguzhaojin.cn/dsh --token <TOKEN>
  python3 scripts/dsh-check.py --base http://127.0.0.1:3781 --token <TOKEN>
  python3 scripts/dsh-check.py --base ... --token ... --raw      # 打印原始帧
  python3 scripts/dsh-check.py --base ... --token ... --no-send  # 只做 1-4

退出码：0 全部通过；非 0 表示某一环节失败。
"""

import argparse
import base64
import json
import os
import socket
import ssl
import struct
import sys
import time
import urllib.error
import urllib.request
from urllib.parse import urlparse

OK = "\033[32mPASS\033[0m"
FAIL = "\033[31mFAIL\033[0m"
WARN = "\033[33mWARN\033[0m"

failures = []


def report(name, ok, detail=""):
    tag = OK if ok else FAIL
    print(f"[{tag}] {name}" + (f"  {detail}" if detail else ""))
    if not ok:
        failures.append(name)
    return ok


def split_base(base):
    """把 base 拆成 (scheme, host, port, prefix)。prefix 形如 /dsh 或空。"""
    parsed = urlparse(base.rstrip("/"))
    scheme = parsed.scheme or "http"
    host = parsed.hostname
    port = parsed.port or (443 if scheme == "https" else 80)
    prefix = parsed.path.rstrip("/")
    return scheme, host, port, prefix


def http_request(base, path, token=None, cookie=None, method="GET", body=None):
    """发一个请求，返回 (status, headers, body_text)。不跟随重定向。"""
    url = base.rstrip("/") + path
    data = None
    headers = {}
    if body is not None:
        data = json.dumps(body).encode()
        headers["content-type"] = "application/json"
    if cookie:
        headers["cookie"] = cookie
    req = urllib.request.Request(url, data=data, headers=headers, method=method)

    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, *a, **k):
            return None

    opener = urllib.request.build_opener(NoRedirect)
    try:
        with opener.open(req, timeout=20) as resp:
            return resp.status, dict(resp.headers), resp.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, dict(e.headers), e.read().decode("utf-8", "replace")


def step_authenticate(base, token):
    """步骤 1：用 launch token 换持久 cookie。"""
    print("\n=== 1. 认证 ===")
    status, headers, _ = http_request(base, f"/?token={urllib.parse.quote(token)}")
    ok = status == 303
    report("返回 303", ok, f"status={status}")

    raw = ""
    for key, value in headers.items():
        if key.lower() == "set-cookie":
            raw = value
            break
    if not report("响应含 Set-Cookie", raw != "", raw[:60] + "..." if raw else "缺失"):
        return None

    cookie = ""
    for segment in raw.split(","):
        for piece in segment.split(";"):
            piece = piece.strip()
            if piece.startswith("dsh-auth-"):
                cookie = piece
                break
        if cookie:
            break
    if not report("cookie 名为 dsh-auth-*", cookie != "", cookie[:40] + "..." if cookie else raw[:80]):
        return None
    return cookie


def rpc(base, cookie, method, args):
    """一元 RPC：POST /api/<ns>/<method>，body 形如 {args:{...}}。"""
    rpc_id = "check-" + str(int(time.time() * 1000))
    envelope = {
        "type": "client-request",
        "rpcId": rpc_id,
        "method": method,
        "payload": {"args": args},
    }
    status, _, text = http_request(
        base, f"/api/{method}", cookie=cookie, method="POST", body=envelope
    )
    if status != 200:
        return False, None, f"HTTP {status}: {text[:160]}"
    try:
        parsed = json.loads(text)
    except json.JSONDecodeError:
        return False, None, f"非 JSON: {text[:160]}"
    if parsed.get("type") != "server-response" or parsed.get("rpcId") != rpc_id:
        return False, None, f"信封不匹配: {text[:160]}"
    result = parsed.get("result") or {}
    if not result.get("ok"):
        err = result.get("error") or {}
        return False, None, f"{err.get('code')}: {err.get('message')}"
    return True, result.get("value"), ""


def step_list(base, cookie):
    print("\n=== 2. 列会话 ===")
    ok, value, err = rpc(base, cookie, "session/list", {"_request": {}})
    if not report("session/list", ok, err):
        return []
    items = value.get("items") or []
    titled = [i for i in items if ((i.get("projections") or {}).get("values") or {}).get("title")]
    report("返回 items 数组", isinstance(items, list), f"共 {len(items)} 个，{len(titled)} 个有标题")
    for item in items[:5]:
        title = ((item.get("projections") or {}).get("values") or {}).get("title") or "(无标题)"
        print(f"        {item.get('sessionId', '')[:28]}  {title[:36]}")
    return items


def step_create(base, cookie):
    print("\n=== 3. 建会话 ===")
    ok, value, err = rpc(base, cookie, "session/create", {"request": {}})
    if not report("session/create", ok, err):
        return None
    session_id = value.get("sessionId") or ""
    report("返回 sessionId", session_id != "", session_id)
    return session_id or None


def step_prompt(base, cookie, session_id, text):
    print("\n=== 4. 发消息 ===")
    args = {
        "request": {
            "requestId": "check-" + str(int(time.time() * 1000)),
            "sessionId": session_id,
            "mode": "queue",
            "content": [{"type": "text", "text": text}],
        }
    }
    ok, value, err = rpc(base, cookie, "session/prompt", args)
    if not report("session/prompt", ok, err):
        return False
    accepted = bool(value.get("accepted")) if isinstance(value, dict) else False
    return report("宿主 accepted", accepted, str(value))


def ws_connect(base, cookie):
    """建立 WebSocket 连接，返回 socket 或 None。"""
    scheme, host, port, prefix = split_base(base)
    path = f"{prefix}/api/remote.mux"
    raw = socket.create_connection((host, port), timeout=20)
    if scheme == "https":
        ctx = ssl.create_default_context()
        sock = ctx.wrap_socket(raw, server_hostname=host)
    else:
        sock = raw
    key = base64.b64encode(os.urandom(16)).decode()
    request = (
        f"GET {path} HTTP/1.1\r\n"
        f"Host: {host}\r\n"
        f"Upgrade: websocket\r\n"
        f"Connection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {key}\r\n"
        f"Sec-WebSocket-Version: 13\r\n"
        f"Cookie: {cookie}\r\n\r\n"
    )
    sock.sendall(request.encode())
    head = sock.recv(4096).decode("utf-8", "replace")
    status_line = head.split("\r\n")[0]
    return sock, status_line


def ws_send(sock, obj):
    payload = json.dumps(obj).encode()
    header = bytearray([0x81])  # FIN + text
    length = len(payload)
    if length < 126:
        header.append(0x80 | length)
    elif length < 65536:
        header.append(0x80 | 126)
        header += struct.pack(">H", length)
    else:
        header.append(0x80 | 127)
        header += struct.pack(">Q", length)
    mask = os.urandom(4)
    header += mask
    masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
    sock.sendall(bytes(header) + masked)


def ws_recv(sock):
    """读一帧，返回 (opcode, text) 或 None。自动回 pong。"""
    head = sock.recv(2)
    if len(head) < 2:
        return None
    opcode = head[0] & 0x0F
    length = head[1] & 0x7F
    if length == 126:
        length = struct.unpack(">H", sock.recv(2))[0]
    elif length == 127:
        length = struct.unpack(">Q", sock.recv(8))[0]
    data = b""
    while len(data) < length:
        chunk = sock.recv(length - len(data))
        if not chunk:
            break
        data += chunk
    if opcode == 0x9:  # ping
        sock.sendall(bytes([0x8A, 0x80]) + os.urandom(4))
        return ws_recv(sock)
    return opcode, data.decode("utf-8", "replace")


def step_stream(base, cookie, session_id, timeout=90, raw=False):
    """步骤 5：订阅流，等一整个回合收完。"""
    print("\n=== 5. 收流 ===")
    try:
        sock, status_line = ws_connect(base, cookie)
    except Exception as e:
        return report("WebSocket 连接", False, str(e))
    if not report("WebSocket 握手 101", "101" in status_line, status_line):
        sock.close()
        return False

    open_frame = {
        "type": "open",
        "streamId": "check-stream",
        "endpoint": "session/follow",
        # 关键：payload 必须包一层 args，且 assistantStream 必须显式为 true
        "payload": {
            "args": {
                "request": {
                    "address": {"kind": "session", "sessionId": session_id},
                    "maxMessages": 50,
                    "assistantStream": True,
                }
            }
        },
    }
    ws_send(sock, open_frame)

    counts = {}
    streamed = ""
    final_text = ""
    streamed_text_len = 0
    done = False
    deadline = time.time() + timeout
    sock.settimeout(5)

    while time.time() < deadline and not done:
        try:
            frame = ws_recv(sock)
        except socket.timeout:
            continue
        except Exception as e:
            report("读帧", False, str(e))
            break
        if frame is None:
            break
        opcode, text = frame
        if opcode == 0x8:
            break
        if opcode != 0x1:
            continue
        try:
            message = json.loads(text)
        except json.JSONDecodeError:
            continue
        if message.get("type") == "error":
            report("流内错误", False, json.dumps(message.get("error"), ensure_ascii=False))
            break
        if message.get("type") == "end":
            break
        value = message.get("value") or {}
        vtype = value.get("type")

        if vtype == "snapshot":
            counts["snapshot"] = counts.get("snapshot", 0) + 1
            if raw:
                print(f"        snapshot cursor={value.get('cursor')}")
            continue

        if vtype == "event":
            event = value.get("event") or {}
            etype = event.get("type", "?")
            counts[etype] = counts.get(etype, 0) + 1
            if raw:
                print(f"        event {etype}")
            if etype == "assistant/message":
                data = event.get("data") or {}
                message_obj = data.get("message") or {}
                for part in message_obj.get("content") or []:
                    if part.get("type") == "text":
                        final_text += part.get("text", "")
            elif etype == "turn/end":
                done = True
                break
            continue

        if vtype == "assistant-stream":
            frame_obj = value.get("frame") or {}
            ftype = frame_obj.get("type", "?")
            counts[f"stream:{ftype}"] = counts.get(f"stream:{ftype}", 0) + 1
            if ftype == "chunk":
                chunk = frame_obj.get("chunk") or {}
                ctype = chunk.get("type", "?")
                counts[f"chunk:{ctype}"] = counts.get(f"chunk:{ctype}", 0) + 1
                if ctype == "text-delta":
                    streamed += chunk.get("text", "")
                    streamed_text_len += len(chunk.get("text", ""))
            continue

        counts[f"other:{vtype}"] = counts.get(f"other:{vtype}", 0) + 1

    sock.close()

    print("        帧统计: " + json.dumps(counts, ensure_ascii=False, sort_keys=True))
    report("收到 turn/end", done, "" if done else "超时或提前断开")
    report(
        "收到 assistant/message",
        counts.get("assistant/message", 0) > 0,
        f"final 长度 {len(final_text)}",
    )
    report("收到 text-delta 流式增量", streamed_text_len > 0, f"累计 {streamed_text_len} 字符")

    if final_text:
        print("\n--------- 最终回复 ---------")
        print(final_text[:800])
        print("-----------------------------")
    if streamed and streamed != final_text:
        matched = streamed.strip() == final_text.strip()
        report("流式增量与最终消息一致", matched, "" if matched else "两者不同，检查是否漏帧")
    return done and len(final_text) > 0


def main():
    parser = argparse.ArgumentParser(description="DSH 协议自检")
    parser.add_argument("--base", required=True, help="形如 https://host/dsh 或 http://127.0.0.1:3781")
    parser.add_argument("--token", required=True, help="启动日志里的 launch token")
    parser.add_argument("--message", default="用一句话说明你是什么模型", help="测试消息")
    parser.add_argument("--raw", action="store_true", help="打印每一帧")
    parser.add_argument("--no-send", action="store_true", help="只做认证与列会话")
    parser.add_argument("--session", default="", help="复用已有 sessionId，不新建")
    args = parser.parse_args()

    print(f"目标: {args.base}")

    cookie = step_authenticate(args.base, args.token)
    if cookie is None:
        print(f"\n结果: {FAIL} 认证失败，后续跳过")
        return 1

    step_list(args.base, cookie)

    if args.no_send:
        print(f"\n结果: {'通过' if not failures else FAIL}")
        return 0 if not failures else 1

    session_id = args.session or step_create(args.base, cookie)
    if not session_id:
        print(f"\n结果: {FAIL} 拿不到 sessionId")
        return 1

    if not step_prompt(args.base, cookie, session_id, args.message):
        print(f"\n结果: {FAIL} 发送失败")
        return 1

    step_stream(args.base, cookie, session_id, raw=args.raw)

    print()
    if failures:
        print(f"结果: {FAIL} 失败项: {', '.join(failures)}")
        return 1
    print(f"结果: {OK} 全链路通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())
