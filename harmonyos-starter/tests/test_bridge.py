import base64
import importlib.util
import json
from pathlib import Path
import struct
import threading
import time
import unittest

spec = importlib.util.spec_from_file_location('clawmate_bridge', Path(__file__).parents[1] / 'bridge/server.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
APP = {'name': '测试应用', 'bundle': 'com.example.test', 'ability': 'EntryAbility'}
HOST = {'name': 'host', 'bundle': 'com.clawmate.harmonystarter', 'ability': 'EntryAbility'}
PNG = b'\x89PNG\r\n\x1a\n' + b'\0\0\0\rIHDR' + struct.pack('>II', 800, 1280)


class FakeDevice:
    def __init__(self):
        self.commands = []

    def probe(self):
        return True

    def launch(self, app, stop):
        self.commands.append(('launch', app['bundle']))

    def screenshot(self, stop):
        return {'base64': base64.b64encode(PNG).decode(), 'mime': 'image/png', 'width': 800, 'height': 1280}

    def shell(self, command, stop):
        self.commands.append(command)


class BridgeTests(unittest.TestCase):
    def setUp(self):
        self.device = FakeDevice()
        self.bridge = module.Bridge(self.device, [APP], HOST)
        self.session = self.bridge.dispatch('/session/open', {})['id']

    def tearDown(self):
        if self.bridge.active:
            self.bridge.active.timer.cancel()

    def body(self, **kwargs):
        return {'session': self.session, **kwargs}

    def test_real_command_plan_requires_screen_and_converts_normalized_coordinates(self):
        with self.assertRaises(module.BridgeError):
            self.bridge.dispatch('/action', self.body(action={'action': 'click', 'x': 500, 'y': 500}))
        self.bridge.dispatch('/screen', self.body())
        self.bridge.dispatch('/action', self.body(action={'action': 'click', 'x': 1000, 'y': 0}))
        self.assertEqual(self.device.commands[-1], ['uitest', 'uiInput', 'click', 799, 0])
        with self.assertRaises(module.BridgeError):
            self.bridge.dispatch('/action', self.body(action={'action': 'click', 'x': 1, 'y': 2}))

    def test_unknown_app_or_shell_action_never_reaches_device(self):
        for route, body in [('/app/start', self.body(bundle='other')), ('/action', self.body(action={'action': 'shell', 'text': 'id'}))]:
            with self.assertRaises(module.BridgeError):
                self.bridge.dispatch(route, body)
        self.assertEqual(self.device.commands, [])

    def test_cancel_prevents_future_actions_but_allows_return_and_close(self):
        self.bridge.dispatch('/session/cancel', self.body())
        with self.assertRaises(module.BridgeError):
            self.bridge.dispatch('/app/start', self.body(bundle=APP['bundle']))
        self.bridge.dispatch('/host/return', self.body())
        self.bridge.dispatch('/session/close', self.body())
        self.assertEqual(self.device.commands, [('launch', HOST['bundle'])])
        self.assertIsNone(self.bridge.active)

    def test_stale_session_cannot_affect_new_session(self):
        self.bridge.dispatch('/session/close', self.body())
        fresh = self.bridge.dispatch('/session/open', {})['id']
        with self.assertRaises(module.BridgeError):
            self.bridge.dispatch('/session/cancel', self.body())
        self.assertEqual(self.bridge.active.id, fresh)
        self.assertFalse(self.bridge.active.stop.is_set())

    def test_expired_session_reclaimed_without_stealing_active_session(self):
        with self.assertRaises(module.BridgeError):
            self.bridge.dispatch('/session/open', {})
        self.bridge.active.expires_at = time.monotonic() - 1
        fresh = self.bridge.dispatch('/session/open', {})['id']
        self.assertNotEqual(fresh, self.session)

    def test_invalid_coordinates_and_image_headers(self):
        for value in [True, float('nan'), float('inf'), -1, 1001, '500']:
            with self.assertRaises(module.BridgeError):
                module.coordinate(value, 100)
        self.assertEqual(module.image_size(PNG), ('image/png', 800, 1280))
        with self.assertRaises(module.BridgeError):
            module.image_size(b'not an image')

    def test_shell_text_is_quoted_as_data_and_not_host_shell_code(self):
        device = module.Device('/path/to/hdc', 'target')
        commands = []
        device.run = lambda args, stop=None, timeout=15: commands.append(args)
        text = "中文 ' ; $(touch /tmp/never) `id`"
        device.shell(['uitest', 'uiInput', 'text', text])
        import shlex
        self.assertEqual(shlex.split(commands[0][1]), ['uitest', 'uiInput', 'text', text])

    def test_cancel_unblocks_inflight_action_and_close(self):
        started = threading.Event()
        def blocking(command, stop):
            started.set()
            if stop.wait(2):
                raise module.BridgeError('cancelled', 409)
        self.device.shell = blocking
        self.bridge.dispatch('/screen', self.body())
        errors = []
        def execute():
            try:
                self.bridge.dispatch('/action', self.body(action={'action': 'input', 'text': '中文'}))
            except module.BridgeError as error:
                errors.append(error)
        worker = threading.Thread(target=execute)
        worker.start()
        self.assertTrue(started.wait(1))
        self.bridge.dispatch('/session/cancel', self.body())
        self.bridge.dispatch('/session/close', self.body())
        worker.join(1)
        self.assertFalse(worker.is_alive())
        self.assertEqual(len(errors), 1)


if __name__ == '__main__':
    unittest.main()
