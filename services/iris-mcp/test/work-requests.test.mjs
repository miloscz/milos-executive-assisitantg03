import {test} from 'node:test';
import assert from 'node:assert/strict';
import {Client} from '@modelcontextprotocol/sdk/client/index.js';
import {InMemoryTransport} from '@modelcontextprotocol/sdk/inMemory.js';
import {createServer} from '../src/server.mjs';
import {workInputs,workOutput} from '../src/work-requests.mjs';
import {sanitizeMessage} from '../src/safe-transport.mjs';

const requestId='11111111-1111-4111-8111-111111111111';
const base={requestId,id:'synthetic',preparationVersion:'a'.repeat(64)};
const receipt={ok:true,workRequest:{...base,kind:'revision',state:'queued',createdAt:'2026-10-19T05:00:00Z',updatedAt:'2026-10-19T05:00:00Z',text:'Compare the existing options.',confirmationEvidence:'none'}};
test('work tools have exact fields, explicit confirmation and secret-free receipts',()=>{
 assert.equal(Object.keys(workInputs).length,4);
 for(const value of [{...base,decision:'AC2=synthetic-secret'},{...base,decision:'Proposed decision',URL:'https://synthetic.invalid'}])assert.equal(workInputs.iris_prepare_decision.safeParse(value).success,false);
 assert.equal(workInputs.iris_request_preparation_revision.safeParse({...base,topic:'options',instruction:'Compare options',directUserCommand:false}).success,false);
 assert.equal(workOutput.safeParse(receipt).success,true);
 for(const value of [{...receipt,token:'synthetic-hidden'}, {...receipt,workRequest:{...receipt.workRequest,state:'recorded'}},
   {...receipt,workRequest:{...receipt.workRequest,text:'Bearer synthetic-hidden'}}]){
  assert.equal(workOutput.safeParse(value).success,false);
  const wire=sanitizeMessage({jsonrpc:'2.0',id:1,result:{structuredContent:value}});
  assert.ok(!JSON.stringify(wire).includes('synthetic-hidden'));
 }
 assert.deepEqual(sanitizeMessage({jsonrpc:'2.0',id:1,result:{structuredContent:receipt}}).result.structuredContent,receipt);
});
test('real SDK maps work calls only to bounded backend and never bypasses invalid input',async t=>{
 const calls=[];const server=createServer(async()=>({ok:false,error:'unavailable'}),async(name,input)=>{calls.push({name,input});return receipt});
 const client=new Client({name:'synthetic-work',version:'1'});const [a,b]=InMemoryTransport.createLinkedPair();
 await server.connect(a);await client.connect(b);t.after(async()=>{await client.close();await server.close()});
 const tools=(await client.listTools()).tools;assert.equal(tools.length,10);
 const result=await client.callTool({name:'iris_request_preparation_revision',arguments:{...base,topic:'options',instruction:'Compare the existing options.',directUserCommand:true}});
 assert.equal(result.structuredContent.workRequest.state,'queued');assert.equal(calls.length,1);
 try{await client.callTool({name:'iris_confirm_decision',arguments:{requestId,decisionId:requestId,confirmationId:requestId,userConfirmed:false}})}catch{}
 assert.equal(calls.length,1);
 assert.equal(tools.find(t=>t.name==='iris_get_work_request').annotations.readOnlyHint,true);
 assert.equal(tools.find(t=>t.name==='iris_confirm_decision').annotations.readOnlyHint,false);
});
