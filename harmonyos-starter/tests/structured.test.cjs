const { test } = require('node:test');
const assert = require('node:assert/strict');
const { loader } = require('./loader.cjs');
const { RunScope } = loader()('core/RunScope');
const { parseAction } = loader()('core/Domain');

function harness(replies, scope = new RunScope()) {
  let requests = [];
  let logs = [];
  const load = loader({'core/ModelService': {complete: async (settings, body) => {
    requests.push(JSON.parse(JSON.stringify(body)));
    const reply = replies.shift();
    if (reply instanceof Error) throw reply;
    return typeof reply === 'function' ? reply() : reply;
  }}});
  const body = {model:'test', messages:[{role:'user',content:[
    {type:'text',text:'输入14×13'}, {type:'image_url',image_url:{url:'data:image/png;base64,AAAA'}}
  ]}]};
  return {requests,logs,body,run:() => load('core/StructuredModel').structuredModel(
    {}, body, scope, parseAction, {log:line=>logs.push(line),phase(){}})};
}

test('real malformed coordinate reply is regenerated on the same screenshot before execution', async () => {
  const bad = '{"action":"click","x":143,675}';
  const h = harness([bad, '{"action":"click","x":143,"y":675}']);
  assert.deepEqual(await h.run(), {action:'click',x:143,y:675});
  assert.equal(h.requests.length,2);
  assert.deepEqual(h.requests[1].messages[0],h.requests[0].messages[0]);
  assert.equal(h.requests[1].messages[1].content,bad);
  assert.match(h.requests[1].messages[2].content,/未执行/);
  assert.match(h.logs[0],/纠正/);
});

test('pixel coordinates, missing fields and empty terminal results cannot bypass schema validation', async () => {
  const h = harness(['{"action":"click","x":181,"y":2168}',
    '{"action":"done","status":"success"}',
    '{"action":"done","status":"success","summary":"14×13=182"}']);
  assert.equal((await h.run()).summary,'14×13=182');
  assert.equal(h.requests.length,3);
  assert.throws(()=>parseAction('{"action":"done","status":"success","summary":123}'),/summary/);
});

test('labelled click supports target IDs without coordinates and rejects malformed target actions', () => {
  assert.deepEqual(parseAction('{"action":"click","target":"t1"}'),{action:'click',target:'t1'});
  for (const action of [{action:'click',target:''},{action:'click',target:123},{action:'swipe',target:'t1'},
    {action:'home',target:'t1'}]) assert.throws(()=>parseAction(JSON.stringify(action)),/target/);
});

test('persistent malformed replies stop after two corrections with a readable error', async () => {
  const h = harness(Array(3).fill('{"action":"click","x":143,675}'));
  await assert.rejects(h.run(),/模型连续返回无效操作.*合法 JSON/);
  assert.equal(h.requests.length,3);
  assert.equal(h.logs.length,2);
});

test('unlabelled icons are retried with numeric coordinates instead of repeating an invented target', async () => {
  const requests=[];
  const replies=['{"action":"click","target":"×"}','{"action":"click","x":618,"y":447}'];
  const load=loader({'core/ModelService':{complete:async(settings,body)=>{
    requests.push(JSON.parse(JSON.stringify(body)));return replies.shift();
  }}});
  const action=await load('core/StructuredModel').structuredModel({}, {messages:[]},new RunScope(),text=>{
    const item=parseAction(text);
    if(item.target)throw Error('点击目标“×”不在当前屏幕按钮列表中或不唯一');
    return item;
  },{log(){},phase(){}});
  assert.deepEqual(action,{action:'click',x:618,y:447});
  assert.match(requests[1].messages.at(-1).content,/不得再使用 target 字段/);
});

test('network errors and cancellation during correction do not trigger additional requests', async () => {
  const network = harness([Error('HTTP 503')]);
  await assert.rejects(network.run(),/HTTP 503/);
  assert.equal(network.requests.length,1);
  const scope = new RunScope();
  const cancelled = harness(['broken',() => {scope.stop();return '{"action":"click","x":1,"y":2}';}],scope);
  await assert.rejects(cancelled.run(),e=>e.status==='cancelled');
  assert.equal(cancelled.requests.length,2);
});

test('GUI correction never executes bad actions and returns host with the verified calculation', async () => {
  const events = []; const bodies = [];
  const replies = ['{"bundle":"calc","task":"rewritten task"}',
    '{"action":"click","x":143,675}', '{"action":"click","x":143,"y":675}',
    '{"action":"done","status":"success","summary":"14×13=182"}'];
  const load = loader({'core/ModelService': {complete:async(settings,body)=>{
    bodies.push(JSON.parse(JSON.stringify(body)));return replies.shift();
  }}});
  const device = {
    open:async()=>({screenshot:true,actions:true,apps:[{bundle:'calc'}]}),
    startApp:async()=>events.push('start'),
    screenshot:async()=>{events.push('screen');return {width:1256,height:2760,mime:'image/png',base64:'AAAA'};},
    execute:async action=>{events.push(action);return 'submitted';},
    cancel:async()=>events.push('cancel'),returnHost:async()=>events.push('return'),close:async()=>events.push('close')
  };
  const Runner = load('core/AgentRunner').AgentRunner;
  const result=await new Runner({model:'test'},device).run('输入14×13',new RunScope(),{log(){},phase(){}});
  assert.deepEqual(result,{status:'success',message:'14×13=182'});
  assert.deepEqual(events,['start','screen',{action:'click',x:143,y:675},'screen','cancel','return','close']);
  assert.match(bodies[1].messages[1].content[0].text,/原始用户任务：输入14×13/);
  assert.doesNotMatch(bodies[1].messages[1].content[0].text,/rewritten task/);
});

test('model selects measured button labels and a stale target is regenerated before execution', async () => {
  const actions = [];
  const bodies = [];
  const replies = ['{"bundle":"calc","task":"输入15*13"}', '{"action":"click","target":"stale"}',
    '{"action":"click","target":"1"}', '{"action":"done","status":"success","summary":"15×13=195"}'];
  const load=loader({'core/ModelService':{complete:async(settings,body)=>{
    bodies.push(JSON.parse(JSON.stringify(body)));return replies.shift();
  }}});
  const device={
    open:async()=>({screenshot:true,actions:true,apps:[{bundle:'calc'}]}),startApp:async()=>{},
    screenshot:async()=>({base64:'AAAA',mime:'image/png',width:1256,height:2760,
      targets:[{id:'t1',label:'1',x:144,y:786},{id:'t3',label:'3',x:618,y:786}]}),
    execute:async action=>{actions.push(action);return 'target=1';},cancel:async()=>{},returnHost:async()=>{},close:async()=>{}
  };
  const result=await new(load('core/AgentRunner').AgentRunner)({model:'test'},device)
    .run('输入15*13',new RunScope(),{log(){},phase(){}});
  assert.equal(result.message,'15×13=195');
  assert.deepEqual(actions,[{action:'click',target:'t1'}]);
  assert.match(bodies[1].messages[1].content[0].text,/"label":"1"/);
});
