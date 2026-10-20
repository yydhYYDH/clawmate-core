const { test } = require('node:test');
const assert = require('node:assert/strict');
const native = require('node:fs/promises');
const path = require('node:path');
const os = require('node:os');
const { loader } = require('./loader.cjs');

async function harness(t) {
  const folder = await native.mkdtemp(path.join(os.tmpdir(),'clawmate-hm-test-'));
  t.after(() => native.rm(folder,{recursive:true,force:true}));
  const handles = new Map(); let next = 1; let closes = 0; let failRead = false;
  const pref = new Map();
  const fs = {
    OpenMode:{READ_ONLY:0,READ_WRITE:1,CREATE:2,TRUNC:4},
    async open(name,mode) { const handle=await native.open(name,mode===0?'r':'w+');const file={fd:next++};handles.set(file.fd,handle);return file; },
    async close(file) {await handles.get(file.fd).close();handles.delete(file.fd);closes++;},
    async stat(fd) {return typeof fd==='number'?handles.get(fd).stat():native.stat(fd);},
    async read(fd,buffer) {if(failRead)throw Error('read failed');return (await handles.get(fd).read(new Uint8Array(buffer),0,Math.min(3,buffer.byteLength),null)).bytesRead;},
    async write(fd,buffer) {return (await handles.get(fd).write(new Uint8Array(buffer),0,Math.min(7,buffer.byteLength),null)).bytesWritten;},
    async access(name) {try{await native.access(name);return true;}catch{return false;}},
    rename:native.rename, unlink:native.unlink
  };
  const mocks = {
    '@kit.CoreFileKit':{fileIo:fs,fileUri:{FileUri:class{constructor(uri){this.name=path.basename(uri);}}},picker:{}},
    '@kit.MediaLibraryKit':{photoAccessHelper:{}},
    '@kit.ImageKit':{image:{createImageSource(){throw Error('bad image');}}},
    '@kit.ArkTS':{util:{TextEncoder:class{encodeInto(text){return new TextEncoder().encode(text);}},Base64Helper:class{encodeToStringSync(b){return Buffer.from(b).toString('base64');}}}},
    '@kit.ArkData':{preferences:{getPreferences:async()=>({get:async(k,d)=>pref.has(k)?pref.get(k):d,put:async(k,v)=>pref.set(k,v),flush:async()=>{}})}}
  };
  const load = loader(mocks);
  return {folder,files:new (load('platform/Files').Files)({filesDir:folder}),Repo:load('platform/Repository').Repository,
    handles,pref,closes:()=>closes,failRead:()=>{failRead=true;}};
}

test('real temp-file import handles short reads, partial writes, Chinese text, empty input and unique internal paths', async t => {
  const h=await harness(t);const source=path.join(h.folder,'资料.txt');
  await native.writeFile(source,'实验口令是蓝色风车🙂');
  const a=await h.files.importSelected(source,'text');const b=await h.files.importSelected(source,'text');
  assert.equal(a.text,'实验口令是蓝色风车🙂');
  assert.equal(await native.readFile(a.path,'utf8'),a.text);assert.notEqual(a.path,b.path);
  await native.writeFile(source,'');assert.equal((await h.files.importSelected(source,'text')).text,'');
  assert.equal(h.handles.size,0);
});

test('read errors and oversize files close descriptors; unsupported types never import', async t=>{
  const h=await harness(t);const source=path.join(h.folder,'source.txt');await native.writeFile(source,'中文');
  await assert.rejects(h.files.readBounded(source,1),/大小限制/);assert.equal(h.handles.size,0);
  h.failRead();await assert.rejects(h.files.readBounded(source,100),/read failed/);assert.equal(h.handles.size,0);
  await assert.rejects(h.files.importSelected(path.join(h.folder,'unsupported.bin'),'text'),/仅支持/);
});

test('invalid UTF-8 and malformed image never leave a partial asset',async t=>{
  const h=await harness(t);const source=path.join(h.folder,'bad.txt');await native.writeFile(source,Buffer.from([0xff]));
  await assert.rejects(h.files.importSelected(source,'text'),/UTF-8/);
  await assert.rejects(h.files.importSelected(source,'image'),/bad image/);
  assert.equal((await native.readdir(h.folder)).filter(x=>x.startsWith('asset-')).length,0);
  assert.equal(h.handles.size,0);
});

test('notes survive repository recreation and referenced attachments are retained',async t=>{
  const h=await harness(t);const source=path.join(h.folder,'note.txt');await native.writeFile(source,'保存中文');
  const item=await h.files.importSelected(source,'text');const repo=new h.Repo({filesDir:h.folder});
  await repo.loadNotes();const note={id:'n1',text:'回复',createdAt:123,attachments:[item]};
  await repo.saveNotes([note]);
  const fresh=new h.Repo({filesDir:h.folder});assert.deepEqual(await fresh.loadNotes(),[note]);
  await fresh.removeUnused([item],[note],[]);assert.equal(await native.readFile(item.path,'utf8'),'保存中文');
  await fresh.saveNotes([]);await fresh.removeUnused([item],[],[]);await assert.rejects(native.access(item.path));
});

test('corrupt notes cannot be overwritten by a later save',async t=>{
  const h=await harness(t);const filename=path.join(h.folder,'notes-v1.json');await native.writeFile(filename,'broken');
  const repo=new h.Repo({filesDir:h.folder});await assert.rejects(repo.loadNotes());
  await assert.rejects(repo.saveNotes([]),/禁止覆盖/);assert.equal(await native.readFile(filename,'utf8'),'broken');
});

test('settings keep custom address/model, restore classroom key and do not persist manual credentials',async t=>{
  const h=await harness(t);const repo=new h.Repo({filesDir:h.folder});
  await repo.saveSettings({modelUrl:'https://test',model:'model',modelKey:'secret',vision:true,bridgeUrl:'http://test',bridgeToken:'token'});
  const defaults=loader()('core/Types').defaultSettings();
  const restored=await repo.loadSettings();assert.equal(restored.model,'model');assert.equal(restored.modelUrl,'https://test');
  assert.equal(restored.modelKey,defaults.modelKey);assert.equal(restored.bridgeToken,'');
  assert.ok(!Array.from(h.pref.values()).includes('secret'));
});

test('empty values saved by the old form fall back to classroom defaults',async t=>{
  const h=await harness(t);h.pref.set('modelUrl','');h.pref.set('model','   ');
  const defaults=loader()('core/Types').defaultSettings();
  const restored=await new h.Repo({filesDir:h.folder}).loadSettings();
  assert.equal(restored.modelUrl,defaults.modelUrl);assert.equal(restored.model,defaults.model);
  assert.ok(restored.modelKey.length>0);
});
