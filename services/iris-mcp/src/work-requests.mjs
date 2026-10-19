import {z} from 'zod';
import net from 'node:net';
import {lstat} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';

const text=n=>z.string().min(1).max(n).refine(s=>!/[\u0000-\u001f\u007f]/.test(s)
 && !/Bearer\s+|(?:authorization|cookie|access[_ -]?token|refresh[_ -]?token|client[_ -]?secret|accessCode[12]|AC[12])["']?\s*[:=]|\bsk-[A-Za-z0-9_-]{16,}|\beyJ[A-Za-z0-9_-]{20,}\./i.test(s));
const uuid=z.string().regex(/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
const version=z.string().regex(/^[0-9a-f]{64}$/);
const date=z.string().datetime({offset:true});
const topic=z.enum(['overview','options','recommendation','sources','missing','task']);
const base={requestId:uuid,id:text(256),preparationVersion:version};
export const workInputs={
 iris_request_preparation_revision:z.strictObject({...base,topic,instruction:text(1000),directUserCommand:z.literal(true)}),
 iris_prepare_decision:z.strictObject({...base,decision:text(1000)}),
 iris_confirm_decision:z.strictObject({requestId:uuid,decisionId:uuid,confirmationId:uuid,userConfirmed:z.literal(true)}),
 iris_get_work_request:z.strictObject({requestId:uuid})
};
const request=z.strictObject({requestId:uuid,kind:z.enum(['revision','decision']),id:text(256),preparationVersion:version,
 state:z.enum(['queued','awaitingSources','needsAnalysis','completed','awaitingConfirmation','recorded','superseded','expired']),
 createdAt:date,updatedAt:date,text:text(1000),confirmationEvidence:z.enum(['none','callerAttestedAfterReadback']),
 confirmationId:uuid.optional(),expiresAt:date.optional(),resultSummary:text(800).optional(),resultVersion:version.optional()
}).superRefine((r,c)=>{
 if((r.state==='awaitingConfirmation')!==(r.confirmationId!==undefined&&r.expiresAt!==undefined)
 || (r.state==='recorded')!==(r.confirmationEvidence==='callerAttestedAfterReadback')
 || (['awaitingConfirmation','recorded','expired'].includes(r.state)&&r.kind!=='decision')
 || (r.state==='completed'&&(r.resultSummary===undefined||r.resultVersion===undefined)))c.addIssue({code:'custom',message:'Invalid receipt'});
});
export const workOutput=z.strictObject({ok:z.boolean(),workRequest:request.optional(),error:z.enum([
 'invalidRequest','versionChanged','stalePreparation','notPrepared','requestConflict','confirmationExpired',
 'confirmationRequired','notFound','queueFull','workUnavailable','rateLimited']).optional()
}).superRefine((r,c)=>{if(r.ok?(!r.workRequest||r.error!==undefined):(!r.error||r.workRequest!==undefined))c.addIssue({code:'custom',message:'Invalid work result'});});
export const workSocket=fileURLToPath(new URL('../../../.iris-runtime/w.sock',import.meta.url));
const methods={iris_request_preparation_revision:'request_revision',iris_prepare_decision:'prepare_decision',
 iris_confirm_decision:'confirm_decision',iris_get_work_request:'get_request'};
export async function callWork(name,input){
 try{
  if(!workInputs[name])throw new Error();
  const params=workInputs[name].parse(input);
  const parent=await lstat(fileURLToPath(new URL('../../../.iris-runtime',import.meta.url)));
  const info=await lstat(workSocket);
  if(!parent.isDirectory()||parent.isSymbolicLink()||parent.uid!==process.getuid()||(parent.mode&0o077)
   ||!info.isSocket()||info.isSymbolicLink()||info.uid!==process.getuid()||(info.mode&0o777)!==0o600)throw new Error();
  return await new Promise(resolve=>{
   const socket=net.createConnection({path:workSocket});let data=Buffer.alloc(0),done=false;
   const finish=value=>{if(done)return;done=true;socket.destroy();resolve(value)};
   socket.setTimeout(5000,()=>finish({ok:false,error:'workUnavailable'}));
   socket.on('error',()=>finish({ok:false,error:'workUnavailable'}));
   socket.on('connect',()=>socket.write(JSON.stringify({method:methods[name],params})+'\n'));
   socket.on('data',chunk=>{
    data=Buffer.concat([data,chunk]);if(data.length>16384)return finish({ok:false,error:'workUnavailable'});
    if(data.includes(10)){try{finish(workOutput.parse(JSON.parse(data.toString('utf8'))))}catch{finish({ok:false,error:'workUnavailable'})}}
   });
   socket.on('end',()=>finish({ok:false,error:'workUnavailable'}));
  });
 }catch{return {ok:false,error:'workUnavailable'}}
}
