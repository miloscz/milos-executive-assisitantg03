import {open,lstat} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {z} from 'zod';
const date=z.string().datetime({offset:true});
const text=z.string().max(5000).refine(x=>!/[\u0000-\u0008\u000b-\u001f]/.test(x)
  && !/\bsk-[A-Za-z0-9_-]{16,}|\beyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]+\.|Bearer\s+\S+|(?:authorization|set-cookie|cookie|access[_ -]?token|refresh[_ -]?token|client[_ -]?secret|accessCode[12]|AC[12])\s*[:=]/i.test(x));
const short=text.pipe(z.string().max(800));
const link=z.string().url().max(1000).refine(x=>{
 try {const u=new URL(x);return u.protocol==='https:'&&u.hostname==='uuapp.plus4u.net'&&!u.username&&!u.password&&!u.hash
   &&[...u.searchParams.keys()].every(k=>['id','oid','code','bid'].includes(k));}catch{return false;}
});
const identifier=text.pipe(z.string().min(1).max(256));
const item=z.strictObject({id:identifier,title:short,start:date,end:date,sourceURL:link.optional()})
 .refine(x=>Date.parse(x.start)<Date.parse(x.end));
const priority=z.strictObject({id:identifier,title:short,due:date,why:short,nextStep:short,
 decisionNeeded:z.boolean(),sourceURL:link.optional()});
const day=z.string().regex(/^\d{4}-\d{2}-\d{2}$/).refine(x=>{
 const d=new Date(x+'T00:00:00Z');return Number.isFinite(+d)&&d.toISOString().slice(0,10)===x;
});
export const briefingSchema=z.strictObject({schemaVersion:z.literal(1),date:day,
 timezone:z.literal('Europe/Prague'),generatedAt:date,sourceFetchedAt:date,
 calendarCoverage:z.enum(['verified','activeRecordsOnly']),summary:text,warnings:z.array(short).max(8),
 schedule:z.array(item).max(24),priorities:z.array(priority).max(5),
 conflicts:z.array(z.strictObject({start:date,end:date,titles:z.array(short).min(2).max(6)})).max(8)});
const failure=z.strictObject({ok:z.literal(false),error:z.enum(['briefingNotPrepared','briefingUnavailable','invalidRequest','rateLimited'])});
export const briefingOutputSchema=z.strictObject({ok:z.boolean(),error:failure.shape.error.optional(),
 freshness:z.enum(['current','stale']).optional(),briefing:briefingSchema.optional()}).superRefine((value,ctx)=>{
 if(value.ok ? (!value.briefing||!value.freshness||value.error!==undefined)
             : (!value.error||value.briefing!==undefined||value.freshness!==undefined))ctx.addIssue({code:'custom',message:'invalid result'});
});
export const briefingPath=fileURLToPath(new URL('../../../.iris-runtime/morning-briefing.json',import.meta.url));

export async function readBriefing() {
 let file;
 try {
  const directory=await lstat(fileURLToPath(new URL('../../../.iris-runtime',import.meta.url)));
  if(!directory.isDirectory()||directory.isSymbolicLink()||directory.uid!==process.getuid()||(directory.mode&0o077)) throw new Error();
  // O_NOFOLLOW, then validate the opened descriptor to avoid a symlink/size race.
  const {constants}=await import('node:fs');
  file=await open(briefingPath,constants.O_RDONLY|constants.O_NOFOLLOW);
  const info=await file.stat();
  if(!info.isFile()||info.uid!==process.getuid()||(info.mode&0o077)||info.size>24576) throw new Error();
  const buffer=Buffer.alloc(24577);const {bytesRead}=await file.read(buffer,0,buffer.length,0);
  if(bytesRead>24576) throw new Error();
  const briefing=briefingSchema.parse(JSON.parse(buffer.subarray(0,bytesRead).toString('utf8')));
  const age=Date.now()-Date.parse(briefing.sourceFetchedAt);
  if(age < -5000 || Date.parse(briefing.generatedAt)>Date.now()+5000)throw new Error();
  return {ok:true,freshness:age>30*60*1000?'stale':'current',briefing};
 }catch(error){return {ok:false,error:error?.code==='ENOENT'?'briefingNotPrepared':'briefingUnavailable'};}
 finally{await file?.close();}
}
