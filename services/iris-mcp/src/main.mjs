import { safeStdio } from './safe-transport.mjs';
import { createServer } from './server.mjs';

// Incoming JSON-RPC is untrusted and may contain secrets accidentally. Never echo or log input/errors.
// Limit a single line BEFORE SDK JSON parsing; overlong/unterminated messages terminate the connection.
let length = 0;
process.stdin.on('data', chunk => {
  for (const byte of chunk) {
    length = byte === 10 ? 0 : length + 1;
    if (length > 32768) process.exit(1);
  }
});
process.on('uncaughtException', () => process.exit(1));
process.on('unhandledRejection', () => process.exit(1));
const server = createServer();
const transport = safeStdio();
// Validation errors must not echo attacker-controlled property names or values in SDK error messages.
server.server.onerror = () => {};
try { await server.connect(transport); } catch { process.exit(1); }
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => { server.close().finally(() => process.exit(0)); });
