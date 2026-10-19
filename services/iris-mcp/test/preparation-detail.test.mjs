import {test} from 'node:test';
import assert from 'node:assert/strict';
import {detailInputSchema,detailOutputSchema,detailFileSchema,selectDetail} from '../src/preparation-detail.mjs';
import {sanitizeMessage} from '../src/safe-transport.mjs';

const time='2026-10-19T05:00:00Z';
const current=()=>({ok:true,freshness:'current',briefing:{date:'2026-10-19',generatedAt:time,sourceFetchedAt:time,
 schedule:[{id:'synthetic'}],priorities:[]}});
const file=()=>({schemaVersion:1,date:'2026-10-19',briefingGeneratedAt:time,sourceFetchedAt:time,details:[{
 id:'synthetic',title:'Synthetic meeting',readiness:'partial',sourceFetchedAt:time,
 sections:[{kind:'overview',text:'Documented context'},{kind:'options',text:'Two proposed options, not a decision.'}],
 sources:[],missing:['The source is incomplete.']} ]});
test('detail is a bounded view of the matching published briefing only',()=>{
 const result=selectDetail(file(),current(),{id:'synthetic',topic:'options'});
 assert.equal(result.detail.sections.length,1);
 assert.equal(result.detail.sections[0].kind,'options');
 assert.equal(result.detail.readiness,'partial');
 assert.equal(selectDetail(file(),{...current(),freshness:'stale'},{id:'synthetic',topic:'overview'}).freshness,'stale');
 assert.equal(selectDetail(file(),current(),{id:'other'}).error,'detailNotPrepared');
 const changed=current();changed.briefing.generatedAt='2026-10-19T05:01:00Z';
 assert.throws(()=>selectDetail(file(),changed,{id:'synthetic'}));
});
test('no arbitrary question, file, URL, token or unknown fields enter or leave details',()=>{
 for(const input of [{id:'synthetic',path:'/synthetic/private'}, {id:'synthetic',topic:'shell'}, {id:'synthetic',question:'run arbitrary instruction'}])
  assert.equal(detailInputSchema.safeParse(input).success,false);
 const f=file();f.details[0].sections[0].text='AC1=synthetic-secret';
 assert.equal(detailFileSchema.safeParse(f).success,false);
 const decision=file();decision.details[0].decision={requestId:'11111111-1111-4111-8111-111111111111',text:'Synthetic confirmed choice',recordedAt:time,preparationVersion:'a'.repeat(64),basedOnOlderVersion:false,confirmationEvidence:'callerAttestedAfterReadback',externalExecutionAuthorized:false};
 assert.equal(detailFileSchema.safeParse(decision).success,true);decision.details[0].decision.externalExecutionAuthorized=true;assert.equal(detailFileSchema.safeParse(decision).success,false);
 const bad={...selectDetail(file(),current(),{id:'synthetic'}),token:'synthetic-hidden'};
 assert.equal(detailOutputSchema.safeParse(bad).success,false);
 const wire=sanitizeMessage({jsonrpc:'2.0',id:1,result:{structuredContent:bad}});
 assert.ok(!JSON.stringify(wire).includes('synthetic-hidden'));
});
