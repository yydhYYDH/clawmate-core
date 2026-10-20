const { test } = require('node:test');
const assert = require('node:assert/strict');
const { loader } = require('./loader.cjs');
const { decodeUtf8, makeQuestion, parseAction, parsePlan, chatEndpoint } = loader()('core/Domain');
const { RunScope, RunStopped } = loader()('core/RunScope');
const utf8 = text => new TextEncoder().encode(text);
const textFile = { id: '1', name: '资料.txt', kind: 'text', text: '实验口令是蓝色风车', path: '/asset-1', preview: '', size: 36, mime: '' };

test('UTF-8 reads Chinese, supplementary characters, BOM and empty input', () => {
  assert.equal(decodeUtf8(utf8('中文ABC🙂')), '中文ABC🙂');
  assert.equal(decodeUtf8(new Uint8Array([239,187,191,...utf8('你好')])),'你好');
  assert.equal(decodeUtf8(new Uint8Array()), '');
});

test('UTF-8 rejects truncated sequences, overlong encoding, surrogates, binary null and invalid code points', () => {
  for (const bytes of [[0xe4,0xb8], [0xc0,0x80], [0xe0,0x80,0x80], [0xed,0xa0,0x80], [0xf4,0x90,0x80,0x80], [0], [0xff]]) {
    assert.throws(() => decodeUtf8(new Uint8Array(bytes)));
  }
});

test('actual imported text enters the request and removing it removes the content', () => {
  const attached = makeQuestion('model', '口令是什么', [textFile], [], false);
  assert.match(JSON.stringify(attached), /实验口令是蓝色风车/);
  assert.doesNotMatch(JSON.stringify(makeQuestion('model', '口令是什么', [], [], false)), /蓝色风车/);
  assert.equal(attached.messages[1].content[0].type, 'text');
});

test('image requests require vision and loaded image bytes, not merely a file URI', () => {
  const photo = { ...textFile, kind: 'image', text: '', mime: 'image/jpeg' };
  assert.throws(() => makeQuestion('m', '?', [photo], ['data:image/jpeg;base64,AAAA'], false), /视觉/);
  assert.throws(() => makeQuestion('m', '?', [photo], [], true), /完整加载/);
  const request = makeQuestion('m', '?', [photo], ['data:image/jpeg;base64,AAAA'], true);
  assert.equal(request.messages[1].content[1].image_url.url, 'data:image/jpeg;base64,AAAA');
});

test('action schema rejects missing status, invalid coordinates and unrecognized actions', () => {
  for (const object of [{action:'done'}, {action:'click',x:-1,y:1}, {action:'click',x:'1',y:1},
    {action:'swipe',x:1,y:2}, {action:'shell',text:'id'}, {action:'input'}, {action:'done',status:'cancelled'}]) {
    assert.throws(() => parseAction(JSON.stringify(object)));
  }
  assert.equal(parseAction('```json\n{"action":"done","status":"failed","summary":"无法完成"}\n```').status, 'failed');
  assert.equal(parseAction('{"action":"click","x":0,"y":1000}').action, 'click');
});

test('planner must select an allowlisted app and preserve an explicit task', () => {
  assert.throws(() => parsePlan('{"bundle":"unlisted","task":"task"}', ['allowed']));
  assert.deepEqual(parsePlan('{"bundle":"allowed","task":"task"}', ['allowed']), { bundle:'allowed', task:'task' });
});

test('model URL normalization accepts base, v1 and full endpoint and rejects non-HTTP URLs', () => {
  for (const base of ['https://model.test','https://model.test/v1/','https://model.test/v1/chat/completions']) {
    assert.equal(chatEndpoint(base),'https://model.test/v1/chat/completions');
  }
  assert.throws(() => chatEndpoint('file:///tmp/x'));
});

test('cancellation is idempotent and expiry preserves a suspended terminal reason', () => {
  const scope = new RunScope(); let callbacks = 0;
  scope.subscribe(() => callbacks++);
  scope.stop(); scope.stop('failed');
  assert.equal(callbacks,1);
  assert.throws(() => scope.check(), error => error.status === 'cancelled');
  const expired = new RunScope(); expired.limit(-1);
  assert.throws(() => expired.check(), error => error instanceof RunStopped && error.status === 'suspended');
});

test('HTTP cancellation settles without a callback from destroy and ignores a late response', async () => {
  let resolveRequest; let destroys = 0;
  const http = { RequestMethod: {POST:'POST'}, HttpDataType:{STRING:0}, createHttp() {
    return { request: () => new Promise(resolve => {resolveRequest=resolve;}), destroy: () => destroys++ };
  }};
  const requestJson = loader({'@kit.NetworkKit':{http}})('platform/HttpJson').requestJson;
  const scope = new RunScope();
  const pending = requestJson('http://test/', '{}', scope);
  scope.stop();
  await assert.rejects(pending, error => error.status === 'cancelled');
  resolveRequest({responseCode:200,result:'{"ok":true}'});
  assert.ok(destroys >= 1);
});

test('HTTP errors release resources and never expose response content as a success', async () => {
  let destroyed = 0;
  const http = { RequestMethod:{POST:'POST'}, HttpDataType:{STRING:0}, createHttp: () => ({
    request: async () => ({responseCode:401,result:'secret service body'}), destroy: () => destroyed++
  })};
  const request = loader({'@kit.NetworkKit':{http}})('platform/HttpJson').requestJson;
  await assert.rejects(request('http://test','{}',new RunScope()), /HTTP 401/);
  assert.equal(destroyed,1);
});

function agentHarness(options = {}) {
  const events = [];
  let screenshots = 0;
  const device = {
    open: async () => { events.push('open'); if(options.openError) throw Error('open failed');
      return {screenshot:true,actions:true,apps:[{name:'calc',bundle:'calc',ability:'EntryAbility'}]}; },
    startApp: async () => {events.push('start');},
    screenshot: async () => {events.push('screen'); screenshots++; return {base64:'AAAA',mime:'image/png',width:100,height:200};},
    execute: async action => {events.push(action.action); return 'submitted';},
    cancel: async () => {events.push('cancel');},
    returnHost: async () => {events.push('return'); if(options.returnError) throw Error('return failed');},
    close: async () => {events.push('close');}
  };
  let decisions = 0;
  const model = {complete: async () => {
    if (screenshots === 0) return '{"bundle":"calc","task":"test"}';
    decisions++;
    if(options.decider) return options.decider(decisions);
    return decisions === 1 ? '{"action":"click","x":1,"y":2}' : '{"action":"done","status":"success","summary":"verified"}';
  }};
  const Runner = loader({'core/ModelService':model})('core/AgentRunner').AgentRunner;
  return { events, runner:new Runner({model:'test'},device) };
}
const eventCallbacks = {phase(){},log(){}};

test('GUI loop observes after an action and cleans up before returning success', async () => {
  const harness = agentHarness();
  assert.deepEqual(await harness.runner.run('task',new RunScope(),eventCallbacks), {status:'success',message:'verified'});
  assert.deepEqual(harness.events,['open','start','screen','click','screen','cancel','return','close']);
});

test('cancelling while awaiting a model response prevents subsequent device input', async () => {
  let resolveModel;
  const harness = agentHarness({decider:() => new Promise(resolve => {resolveModel=resolve;})});
  const scope = new RunScope();
  const pending = harness.runner.run('task',scope,eventCallbacks);
  await new Promise(resolve => setImmediate(resolve));
  scope.stop(); resolveModel('{"action":"input","text":"late"}');
  await assert.rejects(pending,error => error.status === 'cancelled');
  assert.ok(!harness.events.includes('input'));
  assert.deepEqual(harness.events.slice(-3),['cancel','return','close']);
});

test('initialization failure still cancels/closes and never launches an app', async () => {
  const harness = agentHarness({openError:true});
  await assert.rejects(harness.runner.run('task',new RunScope(),eventCallbacks), /open failed/);
  assert.deepEqual(harness.events,['open','cancel','close']);
});

test('failed outcome is not promoted when returning the host fails', async () => {
  const harness = agentHarness({returnError:true,decider:async () => '{"action":"done","status":"failed","summary":"not completed"}'});
  const result = await harness.runner.run('task',new RunScope(),eventCallbacks);
  assert.equal(result.status,'failed');
  assert.equal(harness.events.at(-1),'close');
});

test('step limit performs a final observation and returns suspended without a thirteenth action', async () => {
  const harness = agentHarness({decider:async () => '{"action":"wait"}'});
  const result = await harness.runner.run('task',new RunScope(),eventCallbacks);
  assert.equal(result.status,'suspended');
  assert.equal(harness.events.filter(x=>x==='wait').length,12);
  assert.equal(harness.events.filter(x=>x==='screen').length,13);
});

test('cross-app switch uses the executor app-start operation and then observes again', async () => {
  const h = agentHarness({decider:async n => n === 1 ? '{"action":"open_app","bundle":"calc"}' :
    '{"action":"done","status":"success","summary":"verified"}'});
  assert.equal((await h.runner.run('task',new RunScope(),eventCallbacks)).status,'success');
  assert.equal(h.events.filter(x=>x==='start').length,2);
  assert.equal(h.events.filter(x=>x==='screen').length,2);
});

test('a model cannot switch to an app outside the device directory', async () => {
  const h = agentHarness({decider:async () => '{"action":"open_app","bundle":"outside"}'});
  await assert.rejects(h.runner.run('task',new RunScope(),eventCallbacks), /目录外/);
  assert.equal(h.events.filter(x=>x==='start').length,1);
  assert.equal(h.events.at(-1),'close');
});

test('classroom Qwen model disables thinking without adding provider options to other models', async () => {
  const requests=[];
  const load=loader({'platform/HttpJson':{requestJson:async(url,body)=>{
    requests.push(JSON.parse(body));return {choices:[{message:{content:'真实正文'}}]};
  }}});
  const complete=load('core/ModelService').complete;
  const defaults=load('core/Types').defaultSettings();
  assert.equal(await complete(defaults,makeQuestion(defaults.model,'你好',[],[],false),new RunScope()),'真实正文');
  assert.deepEqual(requests[0].chat_template_kwargs,{enable_thinking:false});
  const generic={...defaults,model:'another-model'};
  await complete(generic,makeQuestion(generic.model,'你好',[],[],false),new RunScope());
  assert.equal(requests[1].chat_template_kwargs,undefined);
});
