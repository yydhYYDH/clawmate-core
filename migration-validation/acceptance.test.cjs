// Held out from the blind implementer. Run with MIGRATION_TARGET=/absolute/project.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript');
const root = path.join(process.env.MIGRATION_TARGET, 'entry/src/main/ets');
function loader(mocks = {}) {
  const cache = new Map();
  function load(name, parent = root) {
    if (Object.hasOwn(mocks, name)) return mocks[name];
    const filename = path.resolve(parent, name) + '.ets';
    const relative = path.relative(root, filename).replace(/\.ets$/, '');
    if (Object.hasOwn(mocks, relative)) return mocks[relative];
    if (name.startsWith('@')) throw Error('Unmocked SDK: ' + name);
    if (cache.has(filename)) return cache.get(filename).exports;
    const module = { exports: {} }; cache.set(filename, module);
    const source = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
    }).outputText;
    vm.runInThisContext('(function(require,module,exports){' + source + '\n})', { filename })(
      dep => load(dep, path.dirname(filename)), module, module.exports);
    return module.exports;
  }
  return name => load('./' + name);
}
function harness(decide, options = {}) {
  const events = [], requests = [];
  let screenCount = 0;
  const load = loader({'core/ModelService': { complete: async (_settings, body) => {
    requests.push(JSON.parse(JSON.stringify(body)));
    if (!screenCount) return JSON.stringify({bundle:'browser',task:'search and record'});
    return JSON.stringify(await decide(screenCount, body));
  }}});
  const scope = new (load('core/RunScope').RunScope)(30000);
  const device = {
    open: async () => {
      events.push('open');
      if (options.openFails) throw Error('no connection');
      return {screenshot:true,actions:true,apps:[
        {name:'浏览器',bundle:'browser',ability:'Main'},
        {name:'备忘录',bundle:'memo',ability:'Main'}]};
    },
    startApp: async bundle => events.push('start:' + bundle),
    screenshot: async () => {
      events.push('screen'); screenCount++;
      return {width:800,height:1280,mime:'image/jpeg',base64:'AAAA',
        text:screenCount === 1 ? '标题：迁移检验 K7p4；来源 https://example.test/source/K7p4' : '备忘录新建页面'};
    },
    execute: async action => {events.push('action:' + action.action); return '已受理，等待截图';},
    cancel: async () => events.push('cancel'),
    returnHost: async () => {events.push('return'); if(options.returnFails) throw Error('denied');},
    close: async () => events.push('close')
  };
  const runner = new (load('core/AgentRunner').AgentRunner)({model:'held-out'},device);
  return {events, requests, scope, run: () => runner.run('搜索本次资料并保存到备忘录',scope,{log(){},phase(){}})};
}
test('cross-App context retains newly observed title and URL after leaving browser', async () => {
  const h = harness((n,body) => {
    if (n === 1) return {action:'open_app',bundle:'memo',progress:'本次结果：迁移检验 K7p4，https://example.test/source/K7p4'};
    const context = JSON.stringify(body);
    assert.match(context,/迁移检验 K7p4/,'title was lost on App switch');
    assert.match(context,/https:\/\/example\.test\/source\/K7p4/,'source was lost on App switch');
    return {action:'done',status:'failed',summary:'只验证上下文，不声称实际保存'};
  });
  assert.equal((await h.run()).status,'failed');
  assert.deepEqual(h.events.filter(e=>e.startsWith('start:')),['start:browser','start:memo']);
});
test('late response after cancellation cannot send another device action', async () => {
  let finish;
  const h = harness(()=>new Promise(resolve=>{finish=resolve;}));
  const pending = h.run();
  await new Promise(resolve=>setImmediate(resolve));
  h.scope.stop(); finish({action:'input',text:'禁止迟到动作'});
  await assert.rejects(pending,e=>e.status==='cancelled');
  assert.equal(h.events.filter(e=>e.startsWith('action:')).length,0);
  assert.equal(h.events.at(-1),'close');
});
test('partially initialized device is closed without launching another App', async () => {
  const h = harness(()=>({}),{openFails:true});
  await assert.rejects(h.run(),/no connection/);
  assert.ok(!h.events.some(e=>e.startsWith('start:')));
  assert.equal(h.events.at(-1),'close');
});
test('host-return failure preserves failed terminal result and still closes resources', async () => {
  const h = harness(()=>({action:'done',status:'failed',summary:'没有保存'}),{returnFails:true});
  assert.equal((await h.run()).status,'failed');
  assert.equal(h.events.at(-1),'close');
});
test('step exhaustion performs one more observation than actions, with no final unverified action', async () => {
  const h = harness(()=>({action:'wait'}));
  assert.equal((await h.run()).status,'suspended');
  const actions = h.events.filter(e=>e==='action:wait').length;
  assert.ok(actions>0 && actions<=100);
  assert.equal(h.events.filter(e=>e==='screen').length,actions+1);
});
