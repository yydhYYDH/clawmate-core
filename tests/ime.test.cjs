// Run: node --test tests/ime.test.cjs
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.env.CLAW_TYPESCRIPT || '/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript');
const root = path.resolve(__dirname, '../tools/ohos-port-ime/entry/src/main/ets/model');

function harness(isChinese = true) {
  const storage = new Map([['isChinese', isChinese], ['candidateStartInx', 0]]);
  const context = vm.createContext({
    AppStorage: { get: key => storage.get(key), set: (key, value) => storage.set(key, value),
      setOrCreate: (key, value) => storage.set(key, value) }, console
  });
  // Codes from the local OpenHarmony SDK's keyCode definitions.
  const codes = { KEYCODE_0: 2000, KEYCODE_9: 2009, KEYCODE_A: 2017, KEYCODE_Z: 2042,
    KEYCODE_SHIFT_LEFT: 2047, KEYCODE_SHIFT_RIGHT: 2048, KEYCODE_ALT_LEFT: 2045,
    KEYCODE_ALT_RIGHT: 2046, KEYCODE_NUMPAD_0: 2103, KEYCODE_NUMPAD_9: 2112 };
  const mocks = { '@ohos.multimodalInput.keyCode': { KeyCode: codes },
    '@ohos.inputMethodEngine': { default: { getInputMethodAbility: () => ({}) } },
    './Log': { default: { showInfo() {} } }, '../common/StyleConfiguration': {} };
  const cache = new Map();
  function load(name, parent = root) {
    if (name in mocks) return mocks[name];
    if (name.startsWith('@')) return {};
    const stem = path.resolve(parent, name);
    const filename = fs.existsSync(stem + '.ets') ? stem + '.ets' : stem + '.ts';
    if (cache.has(filename)) return cache.get(filename).exports;
    const module = { exports: {} };
    cache.set(filename, module);
    const source = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
    }).outputText;
    vm.runInContext('(function(require, module, exports) {' + source + '\n})', context, { filename })(
      name => load(name, path.dirname(filename)), module, module.exports);
    return module.exports;
  }
  const { InputHandler, keyboardController } = load('./KeyboardController');
  const handler = InputHandler.getInstance();
  const inserted = [], messages = [];
  handler.onInputStart({}, { getEditorAttribute: async () => ({}), insertText: text => inserted.push(text) });
  handler.workerInstance = { postMessage: message => messages.push(message) };
  function press(code) {
    assert.equal(keyboardController.onKeyDown({ keyCode: code }), true);
    keyboardController.onKeyUp({ keyCode: code });
  }
  return { handler, inserted, messages, press, storage, MessageType: load('./PinyinMessage').MessageType };
}

test('both digit rows insert all ten digits in Chinese and English mode without candidates', () => {
  for (const chinese of [true, false]) {
    const h = harness(chinese);
    for (const base of [2000, 2103]) for (let i = 0; i < 10; i++) h.press(base + i);
    assert.equal(h.inserted.join(''), '01234567890123456789');
    assert.equal(h.messages.length, 0, 'digits must not go to the pinyin decoder');
  }
});

test('digits 1–7 select a Chinese candidate on either digit row, including subsequent pages', () => {
  for (const base of [2000, 2103]) for (let digit = 1; digit <= 7; digit++) {
    const h = harness();
    h.handler.getDataSource().setData(Array.from({ length: 14 }, (_, i) => String(i)));
    h.storage.set('candidateStartInx', 7);
    h.press(base + digit);
    assert.equal(h.messages[0].type, h.MessageType.CHOOSE);
    assert.equal(h.messages[0].candId, 7 + digit - 1);
    assert.equal(h.inserted.length, 0);
  }
});

test('unavailable candidate digits insert text; pinyin letters still reach the decoder', () => {
  const h = harness();
  h.handler.getDataSource().setData(['你']);
  for (const digit of [0, 2, 8, 9]) h.press(2000 + digit);
  assert.equal(h.inserted.join(''), '0289');
  h.press(2030); // n
  assert.equal(h.messages[0].type, h.MessageType.KEY);
  assert.equal(h.messages[0].keyChar, 'n');
});
