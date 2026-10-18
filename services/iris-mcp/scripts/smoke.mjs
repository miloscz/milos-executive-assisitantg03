// Read-only smoke: never prepare, acknowledge or start a login.
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';
import { fileURLToPath } from 'node:url';
import { outputSchema } from '../src/native-control.mjs';
const launcher=fileURLToPath(new URL('./run-stdio.sh',import.meta.url));
const client=new Client({name:'iris-read-only-check',version:'1'});
const transport=new StdioClientTransport({command:'/bin/bash',args:[launcher],stderr:'pipe'});
try {
  await client.connect(transport);
  const names=(await client.listTools()).tools.map(x=>x.name).sort();
  const expected=['iris_confirm_notice_sent','iris_get_access_status','iris_prepare_login','iris_start_login'];
  if(JSON.stringify(names)!==JSON.stringify(expected)) throw new Error('unexpected_tools');
  const result=await client.callTool({name:'iris_get_access_status',arguments:{}});
  const status=outputSchema.parse(result.structuredContent);
  console.log(JSON.stringify({tools:expected,status}));
  if(!status.ok) process.exitCode=1;
} catch {console.log('{"ok":false,"error":"mcp_check_failed"}');process.exitCode=1;}
finally {await client.close();}
