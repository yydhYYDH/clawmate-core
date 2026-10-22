// Protocol replay derived from official daemon.cpp SendAuthOkMsg:
// HANDSHAKE(AUTH_OK) is immediately followed by CHANNEL_CLOSE(channel=0,count=1).
const { test } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { loader } = require(path.join(process.env.MIGRATION_TARGET, 'tests/loader.cjs'));
const { RunScope } = loader()('core/RunScope');
function vint(n) { const out=[]; do {out.push((n&127)|(n>127?128:0));n=Math.floor(n/128);}while(n);return Buffer.from(out); }
function number(tag,n) {return Buffer.concat([vint(tag*8),vint(n)]);}
function bytes(tag,b) {b=Buffer.from(b);return Buffer.concat([vint(tag*8+2),vint(b.length),b]);}
function packet(channel,command,data) {
  const protect=Buffer.concat([number(1,channel),number(2,command),number(3,0),number(4,9)]);
  const header=Buffer.alloc(11);header.set([72,87,0,0,1]);header.writeUInt16BE(protect.length,5);header.writeUInt32BE(data.length,7);
  return Buffer.concat([header,protect,data]);
}
function decode(raw) {
  const b=Buffer.from(raw); const h=b.readUInt16BE(5);let i=11;const fields={};
  function read() {let n=0,s=0,v;do{v=b[i++];n+=(v&127)*2**s;s+=7;}while(v&128);return n;}
  while(i<11+h){const tag=read();fields[tag>>3]=read();}
  return {channel:fields[1],command:fields[2],data:b.subarray(11+h)};
}
function tlv(key,value) {return Buffer.from(key.padEnd(16,' ')+String(Buffer.byteLength(value)).padEnd(16,' ')+value);}
function harness({status='SUCCESS'}={}) {
  const handlers={},sent=[];
  function emit(b) {handlers.message({message:Uint8Array.from(b).buffer});}
  const tcp={on:(k,cb)=>handlers[k]=cb,off:k=>delete handlers[k],bind:async()=>{},connect:async()=>{},close:async()=>{},
    send:async({data})=>{
      const p=decode(data);sent.push(p);
      if(p.command===1) {
        const auth=Buffer.concat([bytes(1,'OHOS HDC'),number(2,4),bytes(5,Buffer.concat([
          tlv('daemonauthstatus',status),tlv('emgmsg',status==='SUCCESS'?'':'rejected')]))]);
        emit(Buffer.concat([packet(0,1,auth),packet(0,2,Buffer.from([1]))]));
      }
      if(p.command===1001) {
        const marker=p.data.toString().match(/__CLAW_RC_\d+_\d+__/)[0];
        emit(Buffer.concat([packet(p.channel,10,Buffer.from('uid=0\n'+marker+'0\n')),packet(p.channel,2,Buffer.from([1]))]));
      }
    }};
  const Client=loader({'@kit.NetworkKit':{socket:{constructTCPSocketInstance:()=>tcp}}})('platform/SelfHdcClient').SelfHdcClient;
  return {client:new Client('127.0.0.1:8710'),sent};
}
test('AUTH_OK then channel-0 close must be acknowledged before first shell command',async()=>{
  const h=harness(),scope=new RunScope();
  try {
    await h.client.open(scope);
    assert.ok(h.sent.some(p=>p.channel===0&&p.command===2&&p.data[0]===0),
      'open resolved without ACK of the daemon authentication channel close');
    assert.equal(await h.client.shell('id',scope),'uid=0');
  } finally {h.client.close();}
});
test('AUTH_OK carrying DAEMON_UNAUTH is not authorization to issue commands',async()=>{
  const h=harness({status:'DAEMON_UNAUTH'}),scope=new RunScope();
  try {await assert.rejects(h.client.open(scope),/auth|认证|授权|rejected|UNAUTH/i);}
  finally {h.client.close();}
});
