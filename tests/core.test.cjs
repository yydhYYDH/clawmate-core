// Run: node --test tests/core.test.cjs
// Uses DevEco's TypeScript transpiler; no device SDK is executed in these tests.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.env.CLAW_TYPESCRIPT || '/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets/core');
function loader(mocks = {}) {
  const cache = new Map();
  function load(name, parent = root) {
    if (name in mocks) return mocks[name];
    if (name === '@kit.ArkTS') return { JSON };
    const filename = path.resolve(parent, name) + '.ets';
    if (filename in mocks) return mocks[filename];
    if (cache.has(filename)) return cache.get(filename).exports;
    const module = { exports: {} };
    cache.set(filename, module);
    const source = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
    }).outputText;
    vm.runInThisContext('(function(require, module, exports) {' + source + '\n})', { filename })(
      name => load(name, path.dirname(filename)), module, module.exports);
    return module.exports;
  }
  return name => load('./' + name);
}
const config = { hdcIp: '127.0.0.1', hdcPort: 8710 };
const noop = () => {};
function callbacks(contents = []) { return { onLog: noop, onPhase: noop, onStep: noop, onContent: value => contents.push(value) }; }
function deferred() {
  let resolve, reject;
  const promise = new Promise((a, b) => { resolve = a; reject = b; });
  return { promise, resolve, reject };
}
function harness({ open, decider, planner } = {}) {
  let bridge;
  class Bridge {
    constructor(config, log, unavailable) { bridge = this; this.unavailable = unavailable; this.closes = 0; this.starts = 0; this.actions = 0; }
    async open() { if (open) await open(); }
    async close() { this.closes++; }
    cancel() { this.cancelled = true; }
    hasExpired() { return false; }
    async returnHost() {}
    async startApp() { this.starts++; }
    async screenshot() { return { image_b64: 'jpeg', screen_width: 800, screen_height: 1280 }; }
    async guiAction() { this.actions++; }
  }
  class Client {
    cancel() { if (planner) planner.reject(new Error('destroyed')); }
    async chatPlanner() { return planner ? planner.promise : '{"app_name":"设置","package_name":"com.ohos.settings"}'; }
    async chatQwenDecider() { return decider ? decider.promise : '{"action":"done","parameters":{"status":"failed"}}'; }
  }
  const load = loader({ [path.join(root, 'PhoneBridge.ets')]: { PhoneBridge: Bridge },
    [path.join(root, 'CloudModelClient.ets')]: { CloudModelClient: Client } });
  return { Runner: load('AgentRunner').AgentRunner, bridge: () => bridge };
}

test('terminal outcomes never promote failed, aborted, suspended or unspecified done to success', () => {
  const load = loader();
  const parser = load('AgentActionParser').AgentActionParser;
  const result = load('AgentRunState').agentTerminalResult;
  for (const [action, status, expected] of [
    ['done', 'success', 'success'], ['done', 'failed', 'failed'], ['done', 'suspended', 'suspended'],
    ['done', '', 'suspended'], ['abort', 'success', 'failed'], ['stop', '', 'suspended'], ['done', 'cancelled', 'cancelled']
  ]) assert.equal(result(parser.parse(JSON.stringify({ action, parameters: { status } }))).status, expected);
  assert.equal(result(parser.parse('{"action":"done","status":"failed","parameters":{"status":"success"}}')).status, 'failed');
});

test('every planner app name resolves to the same OpenHarmony bundle; explicit bundles still work', () => {
  const load = loader();
  const { PHONE_APPS } = load('AppCatalog');
  const { phoneHdcBundle } = load('selfhdc/PhoneHdcApp');
  for (const app of PHONE_APPS) assert.equal(phoneHdcBundle(app.name, ''), app.bundle);
  assert.equal(phoneHdcBundle('设置', 'com.example.custom'), 'com.example.custom');
});

test('initialization failure releases partially opened bridge', async () => {
  const h = harness({ open: async () => { throw new Error('preflight failed'); } });
  await assert.rejects(new h.Runner(config).run('打开设置', callbacks()), /preflight failed/);
  assert.equal(h.bridge().closes, 1);
  assert.equal(h.bridge().starts, 0);
});

test('cancelling planner wait releases resources and does not launch an app', async () => {
  const planner = deferred();
  const h = harness({ planner });
  const runner = new h.Runner(config);
  const run = runner.run('打开设置', callbacks());
  await new Promise(resolve => setImmediate(resolve));
  runner.cancel();
  await assert.rejects(run, error => error.status === 'cancelled');
  assert.equal(h.bridge().closes, 1);
  assert.equal(h.bridge().starts, 0);
});

test('late decider response after cancellation cannot issue device actions', async () => {
  const decider = deferred();
  const h = harness({ decider });
  const runner = new h.Runner(config);
  const run = runner.run('打开设置', callbacks());
  await new Promise(resolve => setImmediate(resolve));
  runner.cancel();
  decider.resolve('{"action":"click","parameters":{"bbox":[100,100,200,200]}}');
  await assert.rejects(run, error => error.status === 'cancelled');
  assert.equal(h.bridge().actions, 0);
  assert.equal(h.bridge().closes, 1);
});

test('failed model outcome propagates to caller as failed', async () => {
  const h = harness();
  const result = await new h.Runner(config).run('打开设置', callbacks());
  assert.equal(result.status, 'failed');
  assert.equal(h.bridge().closes, 1);
});

test('HTTP cancellation settles even when destroy produces no request callback', async () => {
  let destroyed = 0;
  const load = loader({ '@kit.NetworkKit': { http: {
    RequestMethod: { POST: 'POST' }, HttpDataType: { STRING: 0 },
    createHttp: () => ({ request: () => new Promise(noop), destroy: () => { destroyed++; } })
  } } });
  const Client = load('CloudModelClient').CloudModelClient;
  const client = new Client({ plannerBaseUrl: 'http://example.test', plannerApiKey: '', plannerModel: '' });
  const pending = client.chatPlanner('task');
  client.cancel();
  await assert.rejects(pending, /取消/);
  assert.ok(destroyed > 0);
  await assert.rejects(client.chatPlanner('late task'), /取消/);
});

test('body receipts follow successful actions and terminal outcome follows the next screenshot', async () => {
  let calls = 0;
  const decider = { promise: { then(resolve) {
    resolve(JSON.stringify(calls++ === 0 ? { action: 'click', parameters: { bbox: [100,100,200,200], target_element: '计算器按钮' } } :
      { action: 'done', parameters: { status: 'success' }, progress: '截图显示操作已生效。', summary: '计算完成。' }));
  } } };
  const h = harness({ decider });
  const contents = [];
  const result = await new h.Runner(config).run('计算', callbacks(contents));
  assert.equal(result.status, 'success');
  assert.equal(result.message, '计算完成。');
  assert.equal(h.bridge().actions, 1);
  assert.ok(contents.includes('第 1 步：已点击计算器按钮，正在检查页面变化。'));
  assert.ok(contents.includes('截图显示操作已生效。'));
  assert.equal(h.bridge().closes, 1);
});

test('input-method settings fall back to system Settings when device has no config ability', async () => {
  let target;
  const load = loader({ '@kit.IMEKit': { inputMethod: {
    getSystemInputMethodConfigAbility() { throw new Error('not provided by board'); }
  } }, [path.join(root, 'AppRuntime.ets')]: { AppRuntime: {
    getContext: () => ({ startAbility: async want => { target = want; } })
  } } });
  await load('PhoneInputMethod').PhoneInputMethod.openSettings();
  assert.equal(target.bundleName, 'com.ohos.settings');
  assert.equal(target.abilityName, 'com.ohos.settings.MainAbility');
});
