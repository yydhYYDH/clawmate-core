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
        return {'base64': base64.b64encode(PNG).decode(), 'mime': 'image/png', 'width': 800, 'height': 1280,
                'targets': [{'id': 't0', 'label': '1', 'x': 144, 'y': 786}]}

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

    def test_browser_start_url_is_preserved_and_cannot_be_a_private_file_or_shell_command(self):
        browser = {**APP, 'startUri': 'https://www.baidu.com/'}
        self.assertEqual(module.valid_app(browser)['startUri'], browser['startUri'])
        for url in ['file:///data/private', 'javascript:alert(1)', 'https://user:secret@example.com/', 'https://example.com/\ninvalid']:
            with self.assertRaises(module.BridgeError):
                module.valid_app({**APP, 'startUri': url})
        calls = []
        device = module.Device('/hdc', 'target')
        def execute(parts, stop=None, timeout=15):
            calls.append(parts)
            return 'start ability successfully.'
        device.shell = execute
        device.launch(browser, None)
        self.assertEqual(calls[0][-2:], ['-U', 'https://www.baidu.com/'])
        self.assertEqual(calls[0][-4:-2], ['-A', 'ohos.want.action.viewData'])

    def test_browser_query_is_encoded_inside_configured_search_url_and_cannot_override_host(self):
        browser = {**APP, 'searchUriTemplate': 'https://www.baidu.com/s?wd={query}'}
        bridge = module.Bridge(self.device, [browser], HOST)
        session = bridge.dispatch('/session/open', {})['id']
        captured = []
        self.device.launch = lambda app, stop: captured.append(app)
        try:
            bridge.dispatch('/app/start', {'session': session, 'bundle': APP['bundle'], 'query': '中文 C++ &url=file:///private'})
            from urllib.parse import urlsplit, parse_qs
            parsed = urlsplit(captured[0]['startUri'])
            self.assertEqual(parsed.hostname, 'www.baidu.com')
            self.assertEqual(parse_qs(parsed.query), {'wd': ['中文 C++ &url=file:///private']})
            for template in ['https://{query}/', 'https://www.baidu.com/s?q={query}&x={query}', 'file:///tmp?q={query}']:
                with self.assertRaises(module.BridgeError):module.valid_app({**APP, 'searchUriTemplate': template})
            with self.assertRaises(module.BridgeError):
                self.bridge.dispatch('/app/start', self.body(bundle=APP['bundle'], query='中文'))
        finally:
            bridge.dispatch('/session/close', {'session': session})

    def test_search_input_replaces_and_submits_in_order_without_executing_text_as_shell(self):
        self.bridge.dispatch('/action', self.body(action={'action': 'input', 'text': "OpenHarmony 官网 ' ; id", 'replace': True, 'submit': True}))
        self.assertEqual(self.device.commands, [
            ['uitest', 'uiInput', 'keyEvent', '2072', '2017'],
            ['uitest', 'uiInput', 'keyEvent', '2055'],
            ['uitest', 'uiInput', 'text', "OpenHarmony 官网 ' ; id"],
            ['uitest', 'uiInput', 'keyEvent', '2054']])
        for action in [{'action': 'input', 'text': 'query', 'submit': 'true'}, {'action': 'home', 'replace': True}]:
            with self.assertRaises(module.BridgeError):
                self.bridge.dispatch('/action', self.body(action=action))

    def test_cancel_during_replacement_does_not_type_or_submit_the_search(self):
        commands = []
        def execute(parts, stop):
            commands.append(parts)
            stop.set()
        self.device.shell = execute
        with self.assertRaises(module.BridgeError):
            self.bridge.dispatch('/action', self.body(action={'action': 'input', 'text': 'query', 'replace': True, 'submit': True}))
        self.assertEqual(len(commands), 1)

    def test_browser_search_field_uses_hint_when_empty_and_page_link_has_measured_target(self):
        tree = {'children': [{'attributes': {'bundleName': APP['bundle'], 'focused': 'true'}, 'children': [
            {'attributes': {'type': 'SearchField', 'hint': '搜索或输入网址', 'bounds': '[50,100][700,200]'}},
            {'attributes': {'type': 'link', 'clickable': 'true', 'text': 'OpenHarmony 官网', 'bounds': '[50,400][700,500]'}}]}]}
        targets = module.screen_targets(tree, 800, 1280)
        self.assertEqual([target['label'] for target in targets], ['搜索或输入网址', 'OpenHarmony 官网'])

    def test_visible_browser_text_excludes_other_apps_notifications_and_offscreen_content(self):
        def text(value, bounds='[0,10][100,40]'):
            return {'attributes': {'type': 'Text', 'text': value, 'bounds': bounds}}
        tree = {'children': [
            {'attributes': {'bundleName': 'browser', 'focused': 'true'}, 'children': [
                text('OpenHarmony 官网'), text('OpenHarmony 官网'), text('不允许'), text('offscreen', '[0,1500][100,1600]')]},
            {'attributes': {'bundleName': 'other', 'focused': 'false'}, 'children': [text('private other app')]},
            {'attributes': {'bundleName': 'com.ohos.sceneboard', 'focused': 'true'}, 'children': [text('private notification')]}]}
        self.assertEqual(module.screen_text(tree, 800, 1280), 'OpenHarmony 官网\n不允许')

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

    def test_labelled_target_click_uses_measured_center_and_is_invalidated_after_input(self):
        self.bridge.dispatch('/screen', self.body())
        result = self.bridge.dispatch('/action', self.body(action={'action': 'click', 'target': 't0', 'x': 618, 'y': 786}))
        self.assertEqual(self.device.commands[-1], ['uitest', 'uiInput', 'click', 115, 1005])
        self.assertIn('target=1', result['message'])
        self.assertIn('pixels=(115,1005)', result['message'])
        with self.assertRaises(module.BridgeError):
            self.bridge.dispatch('/action', self.body(action={'action': 'click', 'target': 't0'}))
        self.bridge.dispatch('/screen', self.body())
        with self.assertRaises(module.BridgeError):
            self.bridge.dispatch('/action', self.body(action={'action': 'click', 'target': 'invented'}))

    def test_ui_targets_use_full_screen_bounds_and_ignore_hidden_disabled_and_status_bar(self):
        def button(text, bounds, **attributes):
            return {'attributes': {'type': 'Button', 'clickable': 'true', 'bounds': bounds, **attributes},
                    'children': [{'attributes': {'type': 'Text', 'text': text}}]}
        tree = {'children': [
            {'attributes': {'bundleName': 'calc', 'focused': 'true'}, 'children': [
                button('1', '[59,2047][304,2290]'), button('3', '[654,2047][899,2290]'),
                button('', '[654,1112][899,1354]'),
                button('hidden', '[0,0][50,50]', visible='false'),
                button('disabled', '[0,0][50,50]', enabled='false'),
                button('clipped', '[-10,0][50,50]')]},
            {'attributes': {'bundleName': 'com.ohos.sceneboard', 'focused': 'true'},
             'children': [button('private notification', '[0,0][50,50]')]}
        ]}
        targets = module.screen_targets(tree, 1256, 2760)
        self.assertEqual([target['label'] for target in targets], ['1', '3', ''])
        self.assertEqual(module.coordinate(targets[0]['x'], 1256), 181)
        self.assertEqual(module.coordinate(targets[0]['y'], 2760), 2168)
        self.assertEqual(module.coordinate(targets[1]['x'], 1256), 776)
        self.assertEqual(module.screen_targets(tree, 1, 1), [])

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
