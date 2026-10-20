import importlib.util
import io
import json
from pathlib import Path
import unittest


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).parents[1] / 'bridge' / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


model = load('classroom', 'classroom_model.py')
bridge = load('bridge_http', 'server.py')


class FakeSocket:
    def __init__(self, request):
        self.input = io.BytesIO(request)
        self.output = io.BytesIO()

    def makefile(self, mode, *args):
        return self.input if mode == 'rb' else self.output

    def sendall(self, data):
        self.output.write(data)

    def settimeout(self, timeout):
        pass


def exchange(handler, route, body, token='t' * 32):
    encoded = json.dumps(body).encode()
    request = (f'POST {route} HTTP/1.0\r\nAuthorization: Bearer {token}\r\nContent-Length: {len(encoded)}\r\n\r\n').encode() + encoded
    connection = FakeSocket(request)
    handler(connection, ('127.0.0.1', 1234), object())
    response = connection.output.getvalue()
    header, payload = response.split(b'\r\n\r\n', 1)
    return int(header.split(b' ')[1]), json.loads(payload)


class HTTPTests(unittest.TestCase):
    def test_model_response_changes_with_actual_request(self):
        handler = model.handler_for('t' * 32)
        body = {'messages': [{'role': 'user', 'content': [{'type': 'text', 'text': '实验口令是蓝色风车'}]}]}
        status, reply = exchange(handler, '/v1/chat/completions', body)
        self.assertEqual(status, 200)
        self.assertIn('确实包含', reply['choices'][0]['message']['content'])
        body['messages'][0]['content'][0]['text'] = '移除了附件'
        _, reply = exchange(handler, '/v1/chat/completions', body)
        self.assertIn('未包含', reply['choices'][0]['message']['content'])

    def test_model_requires_auth_and_refuses_fake_gui_success(self):
        handler = model.handler_for('t' * 32)
        body = {'messages': [{'role': 'system', 'content': '你是任务规划器'}]}
        self.assertEqual(exchange(handler, '/v1/chat/completions', body, 'wrong')[0], 401)
        self.assertEqual(exchange(handler, '/v1/chat/completions', body)[0], 400)

    def test_model_rejects_device_uri_as_image_data(self):
        body = {'messages': [{'content': [{'type': 'image_url', 'image_url': {'url': 'file://media/Photo/1'}}]}]}
        self.assertEqual(exchange(model.handler_for('t' * 32), '/v1/chat/completions', body)[0], 400)

    def test_bridge_auth_happens_before_dispatch(self):
        class Stub:
            def __init__(self):
                self.calls = []
            def dispatch(self, route, body):
                self.calls.append(route)
                return {'ok': True}
        stub = Stub()
        handler = bridge.handler_for(stub, 't' * 32)
        self.assertEqual(exchange(handler, '/capabilities', {}, 'wrong')[0], 401)
        self.assertEqual(stub.calls, [])
        self.assertEqual(exchange(handler, '/capabilities', {})[0], 200)
        self.assertEqual(stub.calls, ['/capabilities'])


if __name__ == '__main__':
    unittest.main()
