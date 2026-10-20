#!/usr/bin/env python3
"""Deterministic request-inspection service for first-run teaching, not an LLM."""
import argparse
import hmac
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


def answer(body):
    messages = body.get('messages')
    if not isinstance(messages, list) or not messages:
        raise ValueError('messages must be a nonempty array')
    texts = []
    images = 0
    for message in messages:
        if not isinstance(message, dict):
            raise ValueError('message must be an object')
        content = message.get('content', '')
        if isinstance(content, str):
            texts.append(content)
        elif isinstance(content, list):
            for part in content:
                if not isinstance(part, dict):
                    raise ValueError('part must be an object')
                if part.get('type') == 'text' and isinstance(part.get('text'), str):
                    texts.append(part['text'])
                elif part.get('type') == 'image_url':
                    url = part.get('image_url', {}).get('url', '')
                    if not isinstance(url, str) or not url.startswith('data:image/') or ';base64,' not in url:
                        raise ValueError('image must contain actual data, not a device URI')
                    import base64
                    encoded = url.split(';base64,', 1)[1]
                    if not base64.b64decode(encoded, validate=True):
                        raise ValueError('image data is empty')
                    images += 1
        else:
            raise ValueError('unsupported content')
    combined = '\n'.join(texts)
    if '你是任务规划器' in combined or '根据当前真实截图决定一个动作' in combined:
        raise ValueError('Classroom inspection service cannot plan or execute GUI tasks. Configure a real vision model.')
    marker = '实验口令是蓝色风车' in combined
    reply = '[课堂测试响应，非大模型]\n'
    reply += '本次请求确实包含资料口令：蓝色风车。\n' if marker else '本次请求未包含资料口令。\n'
    reply += f'收到 {images} 张图片的实际字节；未进行图像语义识别。\n'
    reply += f'收到文本共 {len(combined)} 个字符。此服务仅用于验证请求构造、附件和笔记流程。'
    return {'choices': [{'message': {'role': 'assistant', 'content': reply}}]}


def handler_for(token):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, format, *args):
            print('classroom inspection:', self.command, self.path)

        def do_POST(self):
            self.connection.settimeout(10)
            if not hmac.compare_digest(self.headers.get('Authorization', ''), 'Bearer ' + token):
                self.reply(401, {'error': 'Authentication required'})
                return
            if self.path != '/v1/chat/completions':
                self.reply(404, {'error': 'Unknown endpoint'})
                return
            try:
                length = int(self.headers.get('Content-Length', '0'))
                if not 0 < length <= 20 * 1024 * 1024:
                    raise ValueError('Invalid request size')
                body = json.loads(self.rfile.read(length))
                if not isinstance(body, dict):
                    raise ValueError('JSON object required')
                self.reply(200, answer(body))
            except (ValueError, TypeError, AttributeError) as error:
                self.reply(400, {'error': str(error)})

        def reply(self, status, body):
            data = json.dumps(body, ensure_ascii=False).encode()
            self.send_response(status)
            self.send_header('Content-Type', 'application/json; charset=utf-8')
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            try:
                self.wfile.write(data)
            except (BrokenPipeError, ConnectionResetError):
                pass
    return Handler


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bind', default='127.0.0.1')
    parser.add_argument('--port', type=int, default=8766)
    parser.add_argument('--token-file', type=Path, required=True)
    args = parser.parse_args()
    token = args.token_file.read_text().strip()
    if len(token) < 24:
        parser.error('Use a random token of at least 24 characters')
    server = ThreadingHTTPServer((args.bind, args.port), handler_for(token))
    server.daemon_threads = True
    print('Classroom request inspection service; NOT an LLM:', args.bind, args.port)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == '__main__':
    main()
