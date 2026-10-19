import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { outputSchema } from './native-control.mjs';
import {briefingOutputSchema} from './briefing.mjs';
import {detailOutputSchema} from './preparation-detail.mjs';
import {workOutput} from './work-requests.mjs';

export function sanitizeMessage(message) {
  if (message.error) {
    const codes = new Set([-32700, -32600, -32601, -32602, -32603]);
    const code = codes.has(message.error.code) ? message.error.code : -32603;
    return { jsonrpc: '2.0', id: message.id ?? null, error: { code, message: 'MCP request rejected' } };
  }
  if (message.result?.isError || message.result?.structuredContent) {
    let value;
    try { value = message.result.structuredContent?.workRequest || ['versionChanged','stalePreparation','notPrepared','requestConflict','confirmationExpired','confirmationRequired','notFound','queueFull','workUnavailable'].includes(message.result.structuredContent?.error)
      ? workOutput.parse(message.result.structuredContent)
      : message.result.structuredContent?.detail || ['detailUnavailable','detailNotPrepared'].includes(message.result.structuredContent?.error)
      ? detailOutputSchema.parse(message.result.structuredContent)
      : message.result.structuredContent?.briefing || ['briefingUnavailable','briefingNotPrepared'].includes(message.result.structuredContent?.error)
      ? briefingOutputSchema.parse(message.result.structuredContent) : outputSchema.parse(message.result.structuredContent); }
    catch { value = { ok: false, error: 'invalidRequest' }; }
    return { jsonrpc: '2.0', id: message.id, result: {
      isError: !value.ok, structuredContent: value, content: [{ type: 'text', text: JSON.stringify(value) }]
    } };
  }
  return message;
}
export function safeStdio() {
  const transport = new StdioServerTransport(process.stdin, process.stdout, { maxBufferSize: 32768 });
  const send = transport.send.bind(transport);
  transport.send = message => send(sanitizeMessage(message));
  return transport;
}
