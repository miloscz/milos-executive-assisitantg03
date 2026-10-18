import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { sanitizeNative, commandFor, operations, noticeText } from '../src/native-control.mjs';
import { sanitizeMessage } from '../src/safe-transport.mjs';
import { createServer } from '../src/server.mjs';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { InMemoryTransport } from '@modelcontextprotocol/sdk/inMemory.js';

const CANARY = 'SYNTHETIC_SECRET_NEVER_EXPORT_8219';
const native = () => ({ ok: true, enabled: true, sessionValid: false, busy: false, locked: false, hasCredentials: true,
  noticeText: CANARY, state: { phase: 'awaitingNotice', eventID: randomUUID(), noticeID: randomUUID(), workPending: true } });

test('native output is rebuilt; free text and all unapproved fields are suppressed', () => {
  const result = sanitizeNative(JSON.stringify(native()));
  assert.equal(result.noticeText, noticeText);
  assert.ok(!JSON.stringify(result).includes(CANARY));
  for (const key of ['token', 'accessCode1', 'cookie', 'authorization', 'debug']) {
    const fixture = native(); fixture[key] = CANARY;
    assert.deepEqual(sanitizeNative(JSON.stringify(fixture)), { ok: false, error: 'unavailable' });
  }
  const nested = native(); nested.state.token = CANARY;
  assert.equal(sanitizeNative(JSON.stringify(nested)).ok, false);
  const enumAttack = native(); enumAttack.state.phase = CANARY;
  assert.equal(sanitizeNative(JSON.stringify(enumAttack)).ok, false);
  for (const raw of [CANARY, JSON.stringify({ok:false,error:CANARY}), 'x'.repeat(8193)]) {
    assert.deepEqual(sanitizeNative(raw), { ok:false,error:'unavailable' });
  }
});

test('only four operations with exact arguments exist; no shell, URL or credentials', () => {
  assert.equal(Object.keys(operations).length, 4);
  const id = randomUUID();
  assert.deepEqual(commandFor('iris_start_login', {noticeId:id,requestId:id,userCommand:'start_login'}), ['start',id,id,'--direct-user-command']);
  for (const name of ['http', 'read_file', 'exec', 'get_token', '__proto__']) assert.throws(() => commandFor(name, {}));
  for (const extra of [{url:'https://example.invalid'}, {accessCode1:CANARY}, {token:CANARY}, {command:'id'}, {noticeId:CANARY}]) {
    assert.throws(() => commandFor('iris_get_access_status', extra));
  }
  for (const userCommand of [false, true, 'yes', CANARY, undefined]) {
    assert.throws(() => commandFor('iris_start_login', {noticeId:id,requestId:id,userCommand}));
  }
});

test('background status is a strict boolean and older native builds default to disabled', () => {
  assert.equal(sanitizeNative(JSON.stringify(native())).backgroundLoginEnabled, false);
  for (const enabled of [true, false]) {
    assert.equal(sanitizeNative(JSON.stringify({...native(),backgroundLoginEnabled:enabled})).backgroundLoginEnabled, enabled);
  }
  for (const value of [1, 'true', CANARY, null]) {
    assert.deepEqual(sanitizeNative(JSON.stringify({...native(),backgroundLoginEnabled:value})), {ok:false,error:'unavailable'});
  }
});

test('protocol and SDK errors cannot export validation text or data', () => {
  for (const message of [
    {jsonrpc:'2.0',id:1,error:{code:-32602,message:CANARY,data:{token:CANARY}}},
    {jsonrpc:'2.0',id:1,result:{isError:true,content:[{type:'text',text:CANARY}]}},
    {jsonrpc:'2.0',id:1,result:{structuredContent:{ok:true,token:CANARY}}}
  ]) assert.ok(!JSON.stringify(sanitizeMessage(message)).includes(CANARY));
});

async function fixture(t, handler) {
  const server = createServer(handler);
  const client = new Client({name:'synthetic-test',version:'1'});
  const [a,b] = InMemoryTransport.createLinkedPair();
  await server.connect(a); await client.connect(b);
  t.after(async () => { await client.close(); await server.close(); });
  return client;
}

test('real SDK discovery exposes only bounded tools and no resources or sampling', async t => {
  const client = await fixture(t, async () => ({ok:false,error:'unavailable'}));
  const tools = (await client.listTools()).tools;
  assert.deepEqual(tools.map(x=>x.name).sort(),Object.keys(operations).sort());
  for (const tool of tools) {
    assert.equal(tool.inputSchema.additionalProperties, false);
    assert.ok(tool.outputSchema);
    assert.equal(tool.annotations.openWorldHint,false);
  }
  assert.equal(client.getServerCapabilities().resources,undefined);
  assert.equal(client.getServerCapabilities().prompts,undefined);
  await assert.rejects(client.readResource({uri:'file:///synthetic-secret'}));
});

test('SDK rejects invalid tools before invoking the native handler', async t => {
  let calls = 0;
  const client = await fixture(t, async () => { calls++; return {ok:false,error:'unavailable'}; });
  for (const req of [
    {name:'exec',arguments:{command:CANARY}},
    {name:'iris_get_access_status',arguments:{token:CANARY}},
    {name:'iris_start_login',arguments:{noticeId:randomUUID(),requestId:randomUUID()}}
  ]) {
    try { const result=await client.callTool(req); assert.equal(result.isError,true); }
    catch { /* SDK protocol errors are scrubbed by the wire transport. */ }
  }
  assert.equal(calls,0);
});

test('valid start is mapped using only synthetic backend; failure bodies are not reflected', async t => {
  let called;
  const client=await fixture(t, async (name,input) => {called={name,input};return {ok:false,error:'noticeRequired'};});
  const id=randomUUID();
  const result=await client.callTool({name:'iris_start_login',arguments:{noticeId:id,requestId:id,userCommand:'start_login'}});
  assert.equal(called.name,'iris_start_login');
  assert.equal(result.structuredContent.error,'noticeRequired');
});

test('native exceptions and injected output secrets fail closed', async t => {
  const client=await fixture(t,async()=>{throw new Error(CANARY)});
  const result=await client.callTool({name:'iris_get_access_status',arguments:{}});
  assert.ok(!JSON.stringify(result).includes(CANARY));
  assert.equal(result.structuredContent.error,'unavailable');
});

test('concurrency limit does not queue or launch additional native processes', async t => {
  const releases=[];
  const client=await fixture(t,()=>new Promise(resolve=>releases.push(resolve)));
  const call=()=>client.callTool({name:'iris_get_access_status',arguments:{}});
  const a=call(),b=call();
  while(releases.length<2) await new Promise(r=>setImmediate(r));
  const third=await call();
  assert.equal(third.structuredContent.error,'rateLimited');
  releases.forEach(r=>r({ok:false,error:'unavailable'}));
  await Promise.all([a,b]);
});
