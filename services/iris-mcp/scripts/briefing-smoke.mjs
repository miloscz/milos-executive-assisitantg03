// Read only the single prepared briefing through the actual sandboxed stdio bridge.
import {Client} from '@modelcontextprotocol/sdk/client/index.js';
import {StdioClientTransport} from '@modelcontextprotocol/sdk/client/stdio.js';
import {fileURLToPath} from 'node:url';
import {briefingOutputSchema} from '../src/briefing.mjs';
const client=new Client({name:'iris-briefing-check',version:'1'});
try{
 await client.connect(new StdioClientTransport({command:'/bin/bash',args:[fileURLToPath(new URL('./run-stdio.sh',import.meta.url))],stderr:'pipe'}));
 const value=briefingOutputSchema.parse((await client.callTool({name:'iris_get_morning_briefing',arguments:{}})).structuredContent);
 console.log(JSON.stringify(value.ok?{ok:true,date:value.briefing.date,freshness:value.freshness,coverage:value.briefing.calendarCoverage,
  blocks:value.briefing.schedule.length,priorities:value.briefing.priorities.length,conflicts:value.briefing.conflicts.length}:value));
 if(!value.ok)process.exitCode=1;
}catch{console.log('{"ok":false,"error":"briefing_check_failed"}');process.exitCode=1;}
finally{await client.close();}
