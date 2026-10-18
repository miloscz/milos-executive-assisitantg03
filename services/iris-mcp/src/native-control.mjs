import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { homedir, tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { z } from 'zod';

const run = promisify(execFile);
const helper = fileURLToPath(new URL('../../../build/Iris Connect.app/Contents/MacOS/IrisControl', import.meta.url));
export const noticeText = 'Pro pokračování potřebuji přihlášení do +4U. Až řekneš „spusť přihlášení“, vyvolám MFA. Měj připravený telefon.';
const phase = z.enum(['idle', 'awaitingNotice', 'awaitingUser', 'authenticating', 'authenticated', 'failed', 'cancelled', 'interrupted']);
const uuid = z.string().uuid();
const date = z.string().datetime({ offset: true });
const nativeError = z.enum(['invalidRequest', 'unavailable', 'noticeRequired', 'noticeExpired', 'locked', 'credentialsRequired', 'alreadyAuthenticated', 'rateLimited']);
const nativeState = z.strictObject({
  phase, eventID: uuid, noticeID: uuid.optional(), noticeExpiresAt: date.optional(), requestID: uuid.optional(),
  workPending: z.boolean(), lastStartedAt: date.optional()
});
const success = z.strictObject({
  ok: z.literal(true), enabled: z.boolean(), state: nativeState, sessionValid: z.boolean(), busy: z.boolean(),
  locked: z.boolean(), hasCredentials: z.boolean(), backgroundLoginEnabled: z.boolean().optional(), noticeText: z.string().max(512)
});
const failure = z.strictObject({ ok: z.literal(false), error: nativeError });
export const outputSchema = z.strictObject({
  ok: z.boolean(), error: nativeError.optional(), enabled: z.boolean().optional(), sessionValid: z.boolean().optional(),
  busy: z.boolean().optional(), backgroundLoginEnabled: z.boolean().optional(), locked: z.boolean().optional(), credentialEntryRequired: z.boolean().optional(),
  phase: phase.optional(), eventId: uuid.optional(), noticeId: uuid.optional(), noticeExpiresAt: date.optional(),
  requestId: uuid.optional(), workPending: z.boolean().optional(), noticeText: z.literal(noticeText).optional()
});

// Rebuild results from validated fields. Never pass through native text, unknown keys or error details.
export function sanitizeNative(raw) {
  try {
    if (typeof raw !== 'string' || Buffer.byteLength(raw) > 8192) return { ok: false, error: 'unavailable' };
    const value = JSON.parse(raw);
    if (value?.ok === false) return failure.parse(value);
    const input = success.parse(value);
    const state = input.state;
    const output = { ok: true, enabled: input.enabled, sessionValid: input.sessionValid, busy: input.busy,
      locked: input.locked, credentialEntryRequired: !input.hasCredentials, phase: state.phase,
      eventId: state.eventID, workPending: state.workPending, noticeText };
    output.backgroundLoginEnabled = input.backgroundLoginEnabled ?? false;
    if (state.noticeID) output.noticeId = state.noticeID;
    if (state.noticeExpiresAt) output.noticeExpiresAt = state.noticeExpiresAt;
    if (state.requestID) output.requestId = state.requestID;
    return outputSchema.parse(output);
  } catch { return { ok: false, error: 'unavailable' }; }
}

export const operations = Object.freeze({
  iris_get_access_status: z.strictObject({}),
  iris_prepare_login: z.strictObject({}),
  iris_confirm_notice_sent: z.strictObject({ noticeId: uuid }),
  iris_start_login: z.strictObject({ noticeId: uuid, requestId: uuid, userCommand: z.literal('start_login') })
});

export function commandFor(name, input) {
  if (!Object.hasOwn(operations, name)) throw new Error('invalidRequest');
  const args = operations[name].parse(input);
  switch (name) {
    case 'iris_get_access_status': return ['status'];
    case 'iris_prepare_login': return ['prepare'];
    case 'iris_confirm_notice_sent': return ['noticeSent', args.noticeId];
    case 'iris_start_login': return ['start', args.noticeId, args.requestId, '--direct-user-command'];
    default: throw new Error('invalidRequest');
  }
}

export async function callNative(name, input) {
  let args;
  try { args = commandFor(name, input); } catch { return { ok: false, error: 'invalidRequest' }; }
  try {
    const { stdout } = await run(helper, args, {
      shell: false, timeout: 8000, maxBuffer: 8192, encoding: 'utf8', windowsHide: true,
      // Tunnel API keys and the parent process environment never reach the helper.
      env: { HOME: homedir(), PATH: '/usr/bin:/bin', TMPDIR: tmpdir() }
    });
    return sanitizeNative(stdout);
  } catch (error) {
    // Native CLI uses exit 1 for safe errors; never surface stderr, command, stack or unknown output.
    if (error?.code === 1) return sanitizeNative(error.stdout);
    return { ok: false, error: 'unavailable' };
  }
}
