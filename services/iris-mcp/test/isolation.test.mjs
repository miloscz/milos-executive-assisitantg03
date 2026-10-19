import {test} from 'node:test';
import assert from 'node:assert/strict';
import {execFile,spawn} from 'node:child_process';
import {promisify} from 'node:util';
import {readFile,writeFile,unlink} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {homedir} from 'node:os';
import net from 'node:net';
import {Client} from '@modelcontextprotocol/sdk/client/index.js';
import {StdioClientTransport} from '@modelcontextprotocol/sdk/client/stdio.js';
const run=promisify(execFile);
const root=fileURLToPath(new URL('../../../',import.meta.url));
const service=fileURLToPath(new URL('../',import.meta.url)).replace(/\/$/,'');
const launcher=service+'/scripts/run-stdio.sh';
const CANARY='SYNTHETIC_DO_NOT_EXPORT_2317';
const sandboxArgs=[
 '-D',`USER_HOME=${homedir()}`,'-D',`SERVICE_ROOT=${service}`, '-D',`APP_BUNDLE=${root}build/Iris Connect.app`,
 '-D',`AUTH_SOCKET=${homedir()}/Library/Application Support/Iris Connect/auth.sock`,
 '-D',`AUTH_DIRECTORY=${homedir()}/Library/Application Support/Iris Connect`,
 '-D',`BRIEFING_FILE=${root}.iris-runtime/morning-briefing.json`,
 '-D',`WORK_SOCKET=${root}.iris-runtime/w.sock`,
 '-D',`DETAIL_FILE=${root}.iris-runtime/briefing-details.json`,
 '-D',`HELPER=${root}build/Iris Connect.app/Contents/MacOS/IrisControl`,
 '-D',`NODE_BINARY=${process.execPath}`,'-f',service+'/scripts/bridge.sb',process.execPath];

test('OS sandbox denies network, home file contents and arbitrary process execution',async t=>{
 const outside=root+'build/iris-mcp-synthetic-canary.txt';
 await writeFile(outside,CANARY);t.after(()=>unlink(outside));
 const briefingFixture=root+'build/iris-mcp-briefing-fixture.json';
 await writeFile(briefingFixture,'{"synthetic":true}');t.after(()=>unlink(briefingFixture));
 const detailFixture=root+'build/iris-mcp-detail-fixture.json';
 await writeFile(detailFixture,'{"synthetic":true}');t.after(()=>unlink(detailFixture));
 const listener=net.createServer(socket=>socket.destroy());
 await new Promise(r=>listener.listen(0,'127.0.0.1',r));t.after(()=>new Promise(r=>listener.close(r)));
 const port=listener.address().port;
 const code=`
 const fs=require('node:fs'),net=require('node:net'),cp=require('node:child_process');
 const out={};
 try{fs.readFileSync(${JSON.stringify(outside)});out.file='allowed'}catch(e){out.file=e.code}
 try{out.briefing=JSON.parse(fs.readFileSync(${JSON.stringify(briefingFixture)},'utf8')).synthetic===true}catch(e){out.briefing=e.code}
 try{out.detail=JSON.parse(fs.readFileSync(${JSON.stringify(detailFixture)},'utf8')).synthetic===true}catch(e){out.detail=e.code}
 const child=cp.spawnSync('/bin/echo',['synthetic']);out.exec=child.error?.code??'allowed';
 const s=net.connect({host:'127.0.0.1',port:${port}});
 s.on('connect',()=>{out.network='allowed';s.destroy()});
 s.on('error',e=>{out.network=e.code});
 s.on('close',()=>console.log(JSON.stringify(out)));
 `;
 const args=sandboxArgs.map(x=>x.startsWith('BRIEFING_FILE=')?`BRIEFING_FILE=${briefingFixture}`:x.startsWith('DETAIL_FILE=')?`DETAIL_FILE=${detailFixture}`:x);
 const {stdout}=await run('/usr/bin/sandbox-exec',[...args,'-e',code],{timeout:8000});
 const result=JSON.parse(stdout);
 assert.ok(['EPERM','EACCES'].includes(result.file));
 assert.ok(['EPERM','EACCES'].includes(result.exec));
 assert.ok(['EPERM','EACCES'].includes(result.network));
 assert.equal(result.briefing,true);
 assert.equal(result.detail,true);
 assert.ok(!stdout.includes(CANARY));
});

test('wire validation errors contain no untrusted method, parameter or secret text',async t=>{
 const transport=new StdioClientTransport({command:'/bin/bash',args:[launcher],stderr:'pipe'});
 const client=new Client({name:'synthetic-wire',version:'1'});
 await client.connect(transport);t.after(()=>client.close());
 for(const req of [
  {name:CANARY,arguments:{}},
  {name:'iris_get_access_status',arguments:{[CANARY]:CANARY}},
  {name:'iris_start_login',arguments:{noticeId:CANARY,requestId:CANARY,userCommand:CANARY}}
 ]){
  try {const result=await client.callTool(req);assert.equal(result.isError,true);assert.ok(!JSON.stringify(result).includes(CANARY));}
  catch(e){assert.ok(!String(e).includes(CANARY));}
 }
 const tools=(await client.listTools()).tools;
 assert.equal(tools.length,10);
});

test('oversized unterminated input is closed without echoing it',async()=>{
 const child=spawn('/bin/bash',[launcher],{stdio:['pipe','pipe','pipe']});
 let out='',err='';child.stdout.on('data',x=>out+=x);child.stderr.on('data',x=>err+=x);
 child.stdin.on('error',()=>{});
 const exit=new Promise((resolve,reject)=>{child.on('exit',resolve);child.on('error',reject)});
 child.stdin.end(CANARY.repeat(3000));
 assert.equal(await exit,1);assert.equal(out,'');assert.equal(err,'');
});


test('OS sandbox permits only the fixed work socket and rejects another local socket',async t=>{
 const allowed='/private/tmp/iris-work-synthetic-'+process.pid+'.sock';
 const denied='/private/tmp/iris-work-other-'+process.pid+'.sock';
 const servers=[];
 for(const path of [allowed,denied]){
  const server=net.createServer(s=>s.end('synthetic'));
  await new Promise(r=>server.listen(path,r));servers.push(server);
 }
 t.after(async()=>{for(const server of servers)await new Promise(r=>server.close(r))});
 const code=`const net=require('node:net');async function check(path){return new Promise(r=>{const s=net.connect({path});s.on('connect',()=>{s.destroy();r('connected')});s.on('error',e=>r(e.code))})};Promise.all([check(${JSON.stringify(allowed)}),check(${JSON.stringify(denied)})]).then(x=>console.log(JSON.stringify(x)))`;
 const args=sandboxArgs.map(x=>x.startsWith('WORK_SOCKET=')?'WORK_SOCKET='+allowed:x);
 const {stdout}=await run('/usr/bin/sandbox-exec',[...args,'-e',code],{timeout:8000});
 const [a,b]=JSON.parse(stdout);assert.equal(a,'connected');assert.ok(['EPERM','EACCES'].includes(b));
});
