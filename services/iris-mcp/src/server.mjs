import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { operations, outputSchema, callNative } from './native-control.mjs';

const descriptions = {
  iris_get_access_status: ['Zjistit přístup k +4U', 'Čte pouze stav nativního Iris Connect. Zamčený Mac smí přihlášení zahájit jen při backgroundLoginEnabled=true a po novém lidském pokynu. Nevolá +4U a nevrací token ani přihlašovací údaje.'],
  iris_prepare_login: ['Připravit upozornění na MFA', 'Jen zaznamená potřebu přístupu. Nezahájí přihlášení. Pokud relace platí, nevytváří nové upozornění.'],
  iris_confirm_notice_sent: ['Zaznamenat odeslané upozornění', 'Použij až po skutečném odeslání nebo vyslovení upozornění Milošovi hlavní Aidou. Technický návrat nástroje není doručení. Toto není souhlas se spuštěním MFA.'],
  iris_start_login: ['Spustit přihlášení na pokyn Miloše', 'Použij pouze po novém přímém lidském pokynu ke spuštění v reakci na platné upozornění. userCommand je deklarace volajícího, ne kryptografický důkaz souhlasu. Pro opakování stejného pokynu vždy zachovej requestId; nikdy neobnovuj MFA automaticky.']
};

// No HTTP transport, resource/file reads, prompts, shell tool, sampling, elicitation or arbitrary URLs.
export function createServer(native = callNative) {
  const server = new McpServer({ name: 'iris-aida', version: '0.1.0' }, {
    instructions: 'Aida smí používat pouze toto omezené rozhraní Iris. Nikdy přímo nevolej +4U ani jiné +4U pluginy a nezískávej tokeny, kódy, cookies nebo hlavičky. Pořadí: stav → prepare → skutečně upozornit člověka → confirm_notice_sent → čekat na NOVÝ přímý pokyn → start. Žádné MFA bez pokynu, žádné automatické opakování. Toto rozhraní nepotřebuje přístup Aidy k počítači.'
  });
  let active = 0;
  const calls = [];
  for (const [name, inputSchema] of Object.entries(operations)) {
    const [title, description] = descriptions[name];
    server.registerTool(name, {
      title, description, inputSchema, outputSchema,
      annotations: { readOnlyHint: name === 'iris_get_access_status', destructiveHint: false, idempotentHint: true, openWorldHint: false }
    }, async input => {
      let result;
      const now = Date.now();
      while (calls.length && calls[0] < now - 60000) calls.shift();
      if (active >= 2 || calls.length >= 60) {
        const failure = { ok: false, error: 'rateLimited' };
        return { isError: true, structuredContent: failure, content: [{ type: 'text', text: JSON.stringify(failure) }] };
      }
      calls.push(now); active++;
      try { result = outputSchema.parse(await native(name, input)); }
      catch { result = { ok: false, error: 'unavailable' }; }
      finally { active--; }
      return { isError: !result.ok, structuredContent: result, content: [{ type: 'text', text: JSON.stringify(result) }] };
    });
  }
  return server;
}
