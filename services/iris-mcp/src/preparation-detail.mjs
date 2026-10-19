import {open,lstat} from 'node:fs/promises';
import {constants} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {z} from 'zod';
import {readBriefing} from './briefing.mjs';

const text=z.string().max(1800).refine(s=>!/[\u0000-\u0008\u000b-\u001f]/.test(s)
 && !/Bearer\s+|(?:authorization|cookie|access[_ -]?token|refresh[_ -]?token|client[_ -]?secret|accessCode[12]|AC[12])["']?\s*[:=]|\bsk-[A-Za-z0-9_-]{16,}|\beyJ[A-Za-z0-9_-]{20,}\./i.test(s));
const id=text.pipe(z.string().min(1).max(256));
const date=z.string().datetime({offset:true});
const topic=z.enum(['overview','options','recommendation','sources','missing','task']);
const link=z.string().url().max(1000).refine(s=>{try{const u=new URL(s);return u.protocol==='https:'&&u.hostname==='uuapp.plus4u.net'&&!u.username&&!u.password&&!u.hash&&[...u.searchParams.keys()].every(k=>['id','oid','code','bid'].includes(k));}catch{return false;}});
const decision=z.strictObject({requestId:z.string().uuid(),text:text.pipe(z.string().min(1).max(1000)),recordedAt:date,preparationVersion:z.string().regex(/^[0-9a-f]{64}$/),basedOnOlderVersion:z.boolean(),confirmationEvidence:z.literal('callerAttestedAfterReadback'),externalExecutionAuthorized:z.literal(false)});
const detail=z.strictObject({id,decision:decision.optional(),version:z.string().regex(/^[0-9a-f]{64}$/).optional(),title:text.pipe(z.string().max(800)),readiness:z.enum(['partial','ready']),
 sourceFetchedAt:date,sections:z.array(z.strictObject({kind:topic,text})).max(6),
 sources:z.array(z.strictObject({sourceURL:link,pageId:id,quote:text.pipe(z.string().max(800))})).max(3),
 missing:z.array(text.pipe(z.string().max(800))).max(4)}).refine(d=>d.readiness!=='ready'||(d.missing.length===0&&d.sources.length>0));
export const detailFileSchema=z.strictObject({schemaVersion:z.literal(1),date:z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
 briefingGeneratedAt:date,sourceFetchedAt:date,details:z.array(detail).max(14)});
export const detailInputSchema=z.strictObject({id,topic:topic.default('overview')});
export const detailOutputSchema=z.strictObject({ok:z.boolean(),error:z.enum(['detailUnavailable','detailNotPrepared','invalidRequest','rateLimited']).optional(),
 freshness:z.enum(['current','stale']).optional(),date:z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
 generatedAt:date.optional(),topic:topic.optional(),detail:detail.optional()}).superRefine((v,c)=>{
 if(v.ok?(!v.detail||!v.freshness||!v.date||!v.generatedAt||!v.topic||v.error!==undefined)
 :(!v.error||v.detail!==undefined||v.freshness!==undefined||v.date!==undefined||v.generatedAt!==undefined||v.topic!==undefined))c.addIssue({code:'custom',message:'invalid detail result'});
});
export const detailPath=fileURLToPath(new URL('../../../.iris-runtime/briefing-details.json',import.meta.url));

export function selectDetail(file,briefing,input){
 const data=detailFileSchema.parse(file), request=detailInputSchema.parse(input);
 if(!briefing.ok||data.date!==briefing.briefing.date||data.briefingGeneratedAt!==briefing.briefing.generatedAt||data.sourceFetchedAt!==briefing.briefing.sourceFetchedAt)throw new Error();
 if(![...briefing.briefing.schedule,...briefing.briefing.priorities].some(r=>r.id===request.id))return {ok:false,error:'detailNotPrepared'};
 const entry=data.details.find(x=>x.id===request.id);
 if(!entry)return {ok:false,error:'detailNotPrepared'};
 if(Date.parse(entry.sourceFetchedAt)<Date.parse(data.sourceFetchedAt)||Date.parse(entry.sourceFetchedAt)>Date.parse(data.briefingGeneratedAt)+5000)throw new Error();
 return detailOutputSchema.parse({ok:true,freshness:briefing.freshness,date:data.date,generatedAt:data.briefingGeneratedAt,
  topic:request.topic,detail:{...entry,sections:entry.sections.filter(s=>s.kind===request.topic)}});
}

export async function readDetail(input){
 let file;
 try{
  const parent=await lstat(fileURLToPath(new URL('../../../.iris-runtime',import.meta.url)));
  if(!parent.isDirectory()||parent.isSymbolicLink()||parent.uid!==process.getuid()||(parent.mode&0o077))throw new Error();
  file=await open(detailPath,constants.O_RDONLY|constants.O_NOFOLLOW);
  const info=await file.stat();
  if(!info.isFile()||info.nlink!==1||info.uid!==process.getuid()||(info.mode&0o077)||info.size>65536)throw new Error();
  const buffer=Buffer.alloc(65537),{bytesRead}=await file.read(buffer,0,buffer.length,0);
  if(bytesRead>65536)throw new Error();
  return selectDetail(JSON.parse(buffer.subarray(0,bytesRead).toString('utf8')),await readBriefing(),input);
 }catch(e){return {ok:false,error:e?.code==='ENOENT'?'detailNotPrepared':'detailUnavailable'};}
 finally{await file?.close();}
}
