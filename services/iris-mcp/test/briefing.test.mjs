import {test} from 'node:test';
import assert from 'node:assert/strict';
import {briefingSchema} from '../src/briefing.mjs';
import {sanitizeMessage} from '../src/safe-transport.mjs';
const valid=()=>({schemaVersion:1,date:'2026-10-19',timezone:'Europe/Prague',generatedAt:'2026-10-18T16:00:00Z',
 sourceFetchedAt:'2026-10-18T15:59:00Z',calendarCoverage:'activeRecordsOnly',summary:'Synthetic briefing',warnings:[],schedule:[],priorities:[],conflicts:[]});
test('briefing output has no unknown fields, credentials, arbitrary URLs or excessive content',()=>{
 assert.ok(briefingSchema.safeParse(valid()).success);
 for(const change of [{token:'SYNTHETIC'}, {summary:'Bearer SYNTHETIC_SECRET'}, {summary:'sk-SYNTHETIC_SECRET_123456789'},
 {summary:'x'.repeat(5001)}, {timezone:'UTC'}, {date:'2026-02-30'}, {summary:'Cookie: session=SYNTHETIC'},
 {schedule:[{id:'x',title:'safe',start:'2026-10-19T09:00:00Z',end:'2026-10-19T08:00:00Z'}]},
 {schedule:[{id:'x',title:'safe',start:'2026-10-19T08:00:00Z',end:'2026-10-19T09:00:00Z',sourceURL:'https://example.invalid/?token=synthetic'}]}]){
  assert.equal(briefingSchema.safeParse({...valid(),...change}).success,false);
 }
});
test('wire supports only schema-checked briefing content and suppresses injected fields',()=>{
 const message={jsonrpc:'2.0',id:7,result:{structuredContent:{ok:true,freshness:'current',briefing:valid()}}};
 assert.equal(sanitizeMessage(message).result.structuredContent.briefing.date,'2026-10-19');
 message.result.structuredContent.briefing.token='SYNTHETIC_SECRET';
 assert.ok(!JSON.stringify(sanitizeMessage(message)).includes('SYNTHETIC_SECRET'));
});
