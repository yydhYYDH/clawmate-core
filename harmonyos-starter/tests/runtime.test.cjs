const { test } = require('node:test');
const assert = require('node:assert/strict');
const { loader } = require('./loader.cjs');
const { RunScope } = loader()('core/RunScope');

function harness(delay = 60000, denied = false) {
  const cancelled = [];
  let expiry;
  const Runtime = loader({'@kit.BackgroundTasksKit':{backgroundTaskManager:{
    requestSuspendDelay(reason, callback) { if(denied)throw Error('denied');expiry=callback;return {requestId:7,actualDelayTime:delay}; },
    cancelSuspendDelay(id) {cancelled.push(id);}
  }}})('platform/Runtime').Runtime;
  return {Runtime,cancelled,expire:()=>expiry()};
}

test('background lifetime uses actual granted quota and expiry suspends the active task',()=>{
  const h=harness();const scope=new RunScope(120000);
  h.Runtime.begin(scope);h.Runtime.onBackground();
  assert.ok(scope.remaining()<=59000);
  h.expire();assert.throws(()=>scope.check(),e=>e.status==='suspended');
  h.Runtime.finish(scope);assert.deepEqual(h.cancelled,[7]);
});

test('denied background quota suspends instead of pretending the task can continue',()=>{
  const h=harness(0,true);const scope=new RunScope();h.Runtime.begin(scope);h.Runtime.onBackground();
  assert.throws(()=>scope.check(),e=>e.status==='suspended');h.Runtime.finish(scope);
});

test('background denial exposes diagnostic detail without replacing the suspended outcome',()=>{
  const h=harness(0,true);const scope=new RunScope();const logs=[];
  h.Runtime.begin(scope,line=>logs.push(line));h.Runtime.onBackground();
  assert.ok(logs.some(line=>line.includes('短时后台申请失败')&&line.includes('denied')));
  assert.throws(()=>scope.check(),e=>e.status==='suspended');h.Runtime.finish(scope);
});

test('cleanup of an old run does not clear a newer active run',()=>{
  const h=harness();const old=new RunScope();const fresh=new RunScope();
  h.Runtime.begin(old);h.Runtime.begin(fresh);h.Runtime.finish(old);h.Runtime.stop();
  assert.throws(()=>fresh.check(),e=>e.status==='cancelled');h.Runtime.finish(fresh);
});

test('return to foreground releases the previously granted short-task resource',()=>{
  const h=harness();const scope=new RunScope();h.Runtime.begin(scope);h.Runtime.onBackground();h.Runtime.foreground();
  assert.deepEqual(h.cancelled,[7]);h.Runtime.finish(scope);
});
