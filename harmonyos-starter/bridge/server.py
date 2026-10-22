#!/usr/bin/env python3
"""ClawMate development bridge. Uses an explicitly selected, authorized HDC device.

No arbitrary shell endpoint. Each primitive is constructed from validated input.
Actual availability of screen capture and uiInput must be checked on the phone.
"""
from __future__ import annotations

import argparse
import base64
import hmac
import json
import math
from pathlib import Path
import re
import secrets
import shlex
import struct
import subprocess
import tempfile
import threading
import time
from urllib.parse import urlsplit, quote
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class BridgeError(Exception):
    def __init__(self, message, status=400):
        super().__init__(message)
        self.status = status


def coordinate(value, extent):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or not 0 <= value <= 1000:
        raise BridgeError('Coordinates must be finite numbers from 0 to 1000.')
    return min(extent - 1, round(value / 1000 * (extent - 1)))


def screen_targets(tree, width, height):
    """Read button centers in the focused app, in the screenshot coordinate system."""
    targets = []
    if width <= 1 or height <= 1:
        return targets

    def visible(attributes):
        return attributes.get('visible', 'true') != 'false' and attributes.get('enabled', 'true') != 'false'

    def label(node):
        attributes = node.get('attributes', {})
        if not visible(attributes):
            return ''
        text = (attributes.get('text') or attributes.get('hint') or attributes.get('accessibilityText') or '').strip()
        if text:
            return text
        return ' '.join(filter(None, (label(child) for child in node.get('children', []))))

    def visit(node):
        attributes = node.get('attributes', {})
        if not visible(attributes) or len(targets) >= 60:
            return
        kind = attributes.get('type')
        is_field = kind in ('TextInput', 'TextArea', 'SearchField', 'input', 'textfield', 'searchbox')
        is_control = kind in ('Button', 'Text', 'Image', 'button', 'link', 'a') and attributes.get('clickable') == 'true'
        if is_field or is_control:
            text = label(node)
            bounds = re.fullmatch(r'\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]', attributes.get('bounds', ''))
            if bounds:
                left, top, right, bottom = map(int, bounds.groups())
                # Only offer fully visible targets: a clipped control's center may be occluded.
                if 0 <= left < right <= width and 0 <= top < bottom <= height:
                    targets.append({'id': 't' + str(len(targets)), 'label': text[:160],
                                    'x': ((left + right) // 2) / (width - 1) * 1000,
                                    'y': ((top + bottom) // 2) / (height - 1) * 1000})
                    return
        for child in node.get('children', []):
            visit(child)

    for root in tree.get('children', []):
        attributes = root.get('attributes', {})
        if attributes.get('focused') == 'true' and attributes.get('bundleName') != 'com.ohos.sceneboard':
            visit(root)
    return targets


def screen_text(tree, width, height):
    """Visible text from the focused app only, excluding status-bar notifications."""
    lines = []
    seen = set()
    used = 0

    def visit(node):
        nonlocal used
        a = node.get('attributes', {})
        if a.get('visible', 'true') == 'false' or used >= 6000:
            return
        text = (a.get('text') or '').strip()
        bounds = re.fullmatch(r'\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]', a.get('bounds', ''))
        if text and text not in seen and bounds:
            left, top, right, bottom = map(int, bounds.groups())
            if max(left, 0) < min(right, width) and max(top, 0) < min(bottom, height):
                text = text[:min(1000, 6000 - used)]
                lines.append(text)
                seen.add(text)
                used += len(text)
        for child in node.get('children', []):
            visit(child)

    for root in tree.get('children', []):
        a = root.get('attributes', {})
        if a.get('focused') == 'true' and a.get('bundleName') != 'com.ohos.sceneboard':
            visit(root)
    return '\n'.join(lines)


def image_size(data):
    if data.startswith(b'\x89PNG\r\n\x1a\n') and len(data) >= 24:
        width, height = struct.unpack('>II', data[16:24])
        mime = 'image/png'
    elif data.startswith(b'\xff\xd8') and data.endswith(b'\xff\xd9'):
        offset = 2
        width = height = 0
        while offset + 4 <= len(data):
            if data[offset] != 255:
                offset += 1
                continue
            marker = data[offset + 1]
            offset += 2
            if marker in (0xD8, 0xD9) or 0xD0 <= marker <= 0xD7:
                continue
            length = int.from_bytes(data[offset:offset + 2], 'big')
            if length < 2 or offset + length > len(data):
                raise BridgeError('Invalid JPEG length.', 502)
            if marker in (0xC0, 0xC1, 0xC2):
                if length < 7:
                    raise BridgeError('Invalid JPEG frame.', 502)
                height, width = struct.unpack('>HH', data[offset + 3:offset + 7])
                break
            offset += length
        mime = 'image/jpeg'
    else:
        raise BridgeError('Capture did not produce a supported PNG or JPEG.', 502)
    if not 1 <= width <= 16384 or not 1 <= height <= 16384:
        raise BridgeError('Invalid image dimensions.', 502)
    return mime, width, height


def valid_app(item):
    if not isinstance(item, dict):
        raise BridgeError('Application entry must be an object.')
    for key in ('name', 'bundle', 'ability'):
        if not isinstance(item.get(key), str) or not item[key].strip():
            raise BridgeError('Application entry requires name, bundle and ability.')
    for key in ('bundle', 'ability'):
        if not re.fullmatch(r'[A-Za-z0-9_.]+', item[key]):
            raise BridgeError('Invalid application identifier.')
    result = {key: item[key] for key in ('name', 'bundle', 'ability')}
    if 'startUri' in item:
        uri = item['startUri']
        if not isinstance(uri, str) or len(uri) > 2048 or any(ord(c) < 32 for c in uri):
            raise BridgeError('Invalid browser start URI.')
        parsed = urlsplit(uri)
        if parsed.scheme not in ('http', 'https') or not parsed.hostname or parsed.username or parsed.password:
            raise BridgeError('Browser start URI must be an HTTP(S) URL without credentials.')
        result['startUri'] = uri
    if 'searchUriTemplate' in item:
        template = item['searchUriTemplate']
        if not isinstance(template, str) or template.count('{query}') != 1 or len(template) > 2048:
            raise BridgeError('Search URI requires exactly one {query} placeholder.')
        parsed = urlsplit(template)
        if '{query}' not in parsed.query or parsed.scheme not in ('http', 'https') or not parsed.hostname or parsed.username or parsed.password:
            raise BridgeError('Search placeholder must be in an HTTP(S) query without credentials.')
        if any(ord(c) < 32 for c in template):
            raise BridgeError('Invalid search URI template.')
        result['searchUriTemplate'] = template
    return result


class Device:
    def __init__(self, hdc, target, capture='uitest'):
        self.hdc = hdc
        self.target = target
        self.capture_method = capture

    def run(self, arguments, stop=None, timeout=15):
        if stop is not None and stop.is_set():
            raise BridgeError('Session cancelled.', 409)
        process = subprocess.Popen([self.hdc, '-t', self.target, *arguments], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        deadline = time.monotonic() + timeout
        try:
            while True:
                try:
                    output, _ = process.communicate(timeout=0.05)
                    break
                except subprocess.TimeoutExpired:
                    if (stop is not None and stop.is_set()) or time.monotonic() >= deadline:
                        process.kill()
                        process.communicate()
                        raise BridgeError('Device command cancelled or timed out.', 409)
            if stop is not None and stop.is_set():
                raise BridgeError('Session cancelled.', 409)
            text = output.decode('utf-8', 'replace')
            if process.returncode != 0 or re.search(r'(?im)^\s*(?:error\b|\[fail\]|fail(?:ed)?\b)', text):
                raise BridgeError('Device command failed: ' + text[:250], 502)
            return text
        except BaseException:
            if process.poll() is None:
                process.kill()
                process.communicate()
            raise

    def shell(self, parts, stop=None, timeout=15):
        return self.run(['shell', ' '.join(shlex.quote(str(part)) for part in parts)], stop, timeout)

    def probe(self):
        capture_tool = 'uitest' if self.capture_method == 'uitest' else 'snapshot_display'
        self.shell(['which', capture_tool])
        help_text = self.shell(['uitest', 'uiInput', 'help'])
        return all(word in help_text for word in ('click', 'swipe', 'text', 'keyEvent'))

    def launch(self, app, stop):
        command = ['aa', 'start', '-b', app['bundle'], '-a', app['ability']]
        if app.get('startUri'):
            command += ['-A', 'ohos.want.action.viewData', '-U', app['startUri']]
        result = self.shell(command, stop)
        if not re.search(r'(?i)start.*success|success.*start', result):
            raise BridgeError('Application launch not confirmed by aa: ' + result[:200], 502)

    def screenshot(self, stop):
        extension = 'png' if self.capture_method == 'uitest' else 'jpeg'
        remote = '/data/local/tmp/clawmate_lab_' + secrets.token_hex(8) + '.' + extension
        try:
            if self.capture_method == 'uitest':
                self.shell(['uitest', 'screenCap', '-p', remote], stop)
            else:
                self.shell(['snapshot_display', '-f', remote], stop)
            with tempfile.TemporaryDirectory(prefix='clawmate-screen-') as folder:
                destination = str(Path(folder) / ('screen.' + extension))
                self.run(['file', 'recv', remote, destination], stop)
                path = Path(destination)
                if not path.is_file() or not 24 <= path.stat().st_size <= 12 * 1024 * 1024:
                    raise BridgeError('Capture file is missing, empty or exceeds 12 MiB.', 502)
                data = path.read_bytes()
            mime, width, height = image_size(data)
            targets = []
            text = ''
            layout_remote = remote + '.json'
            try:
                self.shell(['uitest', 'dumpLayout', '-p', layout_remote], stop)
                with tempfile.TemporaryDirectory(prefix='clawmate-targets-') as folder:
                    path = Path(folder) / 'layout.json'
                    self.run(['file', 'recv', layout_remote, str(path)], stop)
                    if path.stat().st_size <= 4 * 1024 * 1024:
                        tree = json.loads(path.read_text())
                        targets = screen_targets(tree, width, height)
                        text = screen_text(tree, width, height)
            except Exception:
                # Some apps expose no UI tree; retain screenshot-based coordinates for those apps.
                pass
            finally:
                try:
                    self.shell(['rm', '-f', layout_remote], timeout=3)
                except Exception:
                    pass
            return {'base64': base64.b64encode(data).decode(), 'mime': mime, 'width': width, 'height': height,
                    'targets': targets, 'text': text}
        finally:
            try:
                self.shell(['rm', '-f', remote], timeout=3)
            except Exception:
                pass


class SessionState:
    def __init__(self):
        self.id = secrets.token_urlsafe(24)
        self.stop = threading.Event()
        self.geometry = None
        self.targets = {}
        self.lock = threading.Lock()
        self.expires_at = time.monotonic() + 180
        self.timer = threading.Timer(180, self.stop.set)
        self.timer.daemon = True
        self.timer.start()


class Bridge:
    def __init__(self, device, apps, host):
        self.device = device
        self.apps = [valid_app(app) for app in apps]
        if not self.apps or len({app['bundle'] for app in self.apps}) != len(self.apps):
            raise BridgeError('Configure a nonempty application list with unique bundles.')
        self.host = valid_app(host)
        self.active = None
        self.guard = threading.Lock()

    def session(self, body):
        with self.guard:
            current = self.active
            if current is None or body.get('session') != current.id:
                raise BridgeError('Unknown session.', 409)
            return current

    def check(self, session):
        with self.guard:
            if self.active is not session:
                raise BridgeError('Session superseded.', 409)
        if session.stop.is_set():
            raise BridgeError('Session cancelled or expired.', 409)

    def dispatch(self, route, body):
        if route == '/capabilities':
            try:
                usable = self.device.probe()
                return {'screenshot': usable, 'actions': usable, 'apps': self.apps,
                        'reason': 'Tools found; actual capture/input must still be verified.' if usable else 'uiInput commands unavailable.'}
            except Exception as error:
                return {'screenshot': False, 'actions': False, 'apps': self.apps, 'reason': str(error)}
        if route == '/session/open':
            with self.guard:
                if self.active is not None and time.monotonic() >= self.active.expires_at:
                    old = self.active
                    if not old.lock.acquire(blocking=False):
                        raise BridgeError('Expired session is still stopping.', 409)
                    try:
                        old.stop.set()
                        old.timer.cancel()
                        self.active = None
                    finally:
                        old.lock.release()
                if self.active is not None:
                    raise BridgeError('Another session exists; close it or restart the bridge.', 409)
                self.active = SessionState()
                return {'id': self.active.id}
        session = self.session(body)
        if route == '/session/cancel':
            session.stop.set()
            return {'message': 'Cancelled; no subsequent command will be started.'}
        if route == '/session/close':
            session.stop.set()
            # Wait for an in-flight primitive to leave before allowing a new session.
            with session.lock:
                with self.guard:
                    if self.active is session:
                        self.active = None
            session.timer.cancel()
            return {'message': 'Session closed.'}
        if route == '/host/return':
            with session.lock:
                with self.guard:
                    if self.active is not session:
                        raise BridgeError('Session superseded.', 409)
                self.device.launch(self.host, None)
            return {'message': 'Host launch accepted; verify foreground.'}
        with session.lock:
            self.check(session)
            if route == '/app/start':
                target = next((app for app in self.apps if app['bundle'] == body.get('bundle')), None)
                if target is None:
                    raise BridgeError('Application is not in the configured allowlist.')
                if 'query' in body:
                    query = body['query']
                    if not isinstance(query, str) or not query.strip() or len(query) > 500 or '\0' in query:
                        raise BridgeError('Search query must contain 1 to 500 characters.')
                    if not target.get('searchUriTemplate'):
                        raise BridgeError('Application has no configured search URI.')
                    target = {**target, 'startUri': target['searchUriTemplate'].replace('{query}', quote(query, safe=''))}
                self.device.launch(target, session.stop)
                if session.stop.wait(0.6):
                    raise BridgeError('Session cancelled.', 409)
                session.geometry = None
                session.targets = {}
                return {'message': 'Launch accepted; inspect the next screenshot.'}
            if route == '/screen':
                result = self.device.screenshot(session.stop)
                self.check(session)
                session.geometry = (result['width'], result['height'])
                session.targets = {target['id']: target for target in result.get('targets', [])}
                return result
            if route == '/action':
                return self.action(session, body.get('action'))
        raise BridgeError('Unknown route.', 404)

    def action(self, session, action):
        if not isinstance(action, dict):
            raise BridgeError('Action must be an object.')
        kind = action.get('action')
        detail = ''
        for option in ('replace', 'submit'):
            if option in action and (kind != 'input' or not isinstance(action[option], bool)):
                raise BridgeError('replace and submit must be booleans on input actions.')
        if kind not in ('click', 'swipe', 'input', 'back', 'home', 'wait'):
            raise BridgeError('Unsupported action.')
        if kind == 'wait':
            if session.stop.wait(0.6):
                raise BridgeError('Session cancelled.', 409)
        else:
            command = ['uitest', 'uiInput']
            if kind in ('click', 'swipe'):
                if session.geometry is None:
                    raise BridgeError('Capture a screen before a coordinate action.')
                width, height = session.geometry
                x, y = action.get('x'), action.get('y')
                if 'target' in action:
                    if kind != 'click' or not isinstance(action['target'], str) or action['target'] not in session.targets:
                        raise BridgeError('Click target is absent from the current screen.')
                    target = session.targets[action['target']]
                    x, y = target['x'], target['y']
                    detail = ' target=' + target['label'][:40]
                px, py = coordinate(x, width), coordinate(y, height)
                command += [kind, px, py]
                detail += f' normalized=({x:.1f},{y:.1f}) pixels=({px},{py}) screen={width}x{height}'
                if kind == 'swipe':
                    command += [coordinate(action.get('x2'), width), coordinate(action.get('y2'), height), 600]
            elif kind == 'input':
                text = action.get('text')
                if not isinstance(text, str) or len(text) > 2000 or '\0' in text:
                    raise BridgeError('Invalid input text.')
                if action.get('replace'):
                    self.check(session)
                    self.device.shell(['uitest', 'uiInput', 'keyEvent', '2072', '2017'], session.stop)
                    self.check(session)
                    self.device.shell(['uitest', 'uiInput', 'keyEvent', '2055'], session.stop)
                command += ['text', text]
            else:
                command += ['keyEvent', '2' if kind == 'back' else '1']
            self.check(session)
            self.device.shell(command, session.stop)
            if kind == 'input' and action.get('submit'):
                self.check(session)
                self.device.shell(['uitest', 'uiInput', 'keyEvent', '2054'], session.stop)
            # Do not race a screenshot against an unfinished UI transition.
            if session.stop.wait(0.6):
                raise BridgeError('Session cancelled.', 409)
        session.geometry = None
        session.targets = {}
        return {'message': kind + detail + ' submitted; outcome requires a fresh screenshot.'}


def handler_for(bridge, token):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, format, *args):
            # Never log tokens, file contents, model inputs or injected text.
            print('bridge:', self.command, self.path)

        def do_POST(self):
            self.connection.settimeout(10)
            try:
                supplied = self.headers.get('Authorization', '')
                if not hmac.compare_digest(supplied, 'Bearer ' + token):
                    raise BridgeError('Authentication required.', 401)
                size = int(self.headers.get('Content-Length', '0'))
                if not 0 < size <= 32768:
                    raise BridgeError('Invalid request size.', 413)
                body = json.loads(self.rfile.read(size))
                if not isinstance(body, dict):
                    raise BridgeError('JSON object required.')
                result = bridge.dispatch(self.path, body)
                self.reply(200, result)
            except (ValueError, UnicodeError):
                self.reply(400, {'error': 'Malformed JSON or request size.'})
            except BridgeError as error:
                self.reply(error.status, {'error': str(error)})
            except Exception:
                self.reply(502, {'error': 'Device bridge failure; check device connection and configured tools.'})

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
    parser.add_argument('--hdc', required=True, help='Absolute path to the target-compatible hdc executable')
    parser.add_argument('--target', required=True, help='Explicit HDC target identifier')
    parser.add_argument('--apps', required=True, type=Path, help='Teacher-verified application and host configuration')
    parser.add_argument('--token-file', required=True, type=Path, help='File containing a random token of at least 24 characters')
    parser.add_argument('--bind', default='127.0.0.1', help='Bind a reachable LAN IP explicitly for a physical phone')
    parser.add_argument('--port', type=int, default=8765)
    parser.add_argument('--capture', choices=['uitest', 'snapshot_display'], default='uitest')
    args = parser.parse_args()
    token = args.token_file.read_text().strip()
    if len(token) < 24:
        parser.error('Token must contain at least 24 characters.')
    configuration = json.loads(args.apps.read_text())
    bridge = Bridge(Device(args.hdc, args.target, args.capture), configuration['apps'], configuration['host'])
    server = ThreadingHTTPServer((args.bind, args.port), handler_for(bridge, token))
    server.daemon_threads = True
    print('Development bridge listening on', args.bind, args.port, 'for explicitly selected device', args.target)
    print('This is external HDC development control, not an on-phone self-HDC implementation.')
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        if bridge.active:
            bridge.active.stop.set()
            bridge.active.timer.cancel()
        server.server_close()


if __name__ == '__main__':
    main()
