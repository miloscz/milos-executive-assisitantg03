"""Work-evidence and admission domain. No network, helpers, auth or MCP.

Inputs here are already normalized by a trusted adapter in the future integration.
An arbitrary model's claim that an input is 'plus4u' is NOT authorization.
"""
from datetime import datetime, timedelta, timezone
import hashlib
import json
from pathlib import Path
import sqlite3
from contextlib import contextmanager


@contextmanager
def transaction(db):
    if db.in_transaction:
        db.execute('SAVEPOINT evidence_change')
        try:
            yield
            db.execute('RELEASE evidence_change')
        except BaseException:
            db.execute('ROLLBACK TO evidence_change')
            db.execute('RELEASE evidence_change')
            raise
    else:
        with db:
            yield


def migrate(db):
    version = db.execute('PRAGMA user_version').fetchone()[0]
    tables = {r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")}
    base = {'schema_version','work_items','work_revisions','preparation_steps','knowledge_claims','intake_events','audit_events'}
    if version not in (0, 1, 2, 3) or (tables and not base.issubset(tables)):
        raise ValueError('unsupported_database')
    if version == 0 and tables:
        if db.execute('SELECT version FROM schema_version').fetchall() != [(1,)]:
            raise ValueError('unsupported_database')
    if version == 0 and not tables:
        db.executescript(Path(__file__).with_name('evidence-schema.sql').read_text())
    if version < 2:
        with db:
            db.execute("ALTER TABLE work_items ADD COLUMN identity_basis TEXT NOT NULL DEFAULT 'elementaryActivity'")
            db.execute('CREATE TABLE store_meta(key TEXT PRIMARY KEY,value TEXT NOT NULL)')
            db.execute('CREATE TABLE captures(id TEXT PRIMARY KEY,observed_at TEXT NOT NULL,native_event TEXT NOT NULL,active_at TEXT NOT NULL,calendar_at TEXT NOT NULL,sources_at TEXT NOT NULL,content_hash TEXT NOT NULL,report TEXT NOT NULL)')
            db.execute('CREATE TABLE source_snapshots(hash TEXT PRIMARY KEY,source_ref TEXT NOT NULL,captured_at TEXT NOT NULL,payload TEXT NOT NULL)')
            db.execute('PRAGMA user_version=2')
    if version < 3:
        with db:
            db.execute('CREATE TABLE aida_requests(id TEXT PRIMARY KEY,kind TEXT NOT NULL,item_id TEXT NOT NULL,preparation_version TEXT NOT NULL,binding_ref TEXT NOT NULL,state TEXT NOT NULL,created_at TEXT NOT NULL,updated_at TEXT NOT NULL,expires_at TEXT,payload TEXT NOT NULL,result TEXT,error_code TEXT)')
            db.execute('CREATE TABLE aida_receipts(id TEXT PRIMARY KEY,input_hash TEXT NOT NULL,subject TEXT NOT NULL REFERENCES aida_requests(id),at TEXT NOT NULL)')
            db.execute('PRAGMA user_version=3')


def canonical(value):
    return json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(',', ':'), allow_nan=False)


def digest(value):
    return hashlib.sha256(canonical(value).encode()).hexdigest()


def stamp(value):
    parsed = datetime.fromisoformat(value.replace('Z', '+00:00'))
    if parsed.tzinfo is None:
        raise ValueError('timezone_required')
    return parsed.astimezone(timezone.utc)


def text(value, limit=1000):
    if not isinstance(value, str) or not value.strip() or len(value) > limit:
        raise ValueError('invalid_text')
    return value


def connect(path=':memory:'):
    # Caller owns private storage and locking; demo/tests use memory or tempdir.
    db = sqlite3.connect(path)
    migrate(db)
    db.row_factory = sqlite3.Row
    return db


def upsert_work(db, item, fetched_at):
    required = {'namespace', 'workspace', 'recordId', 'elementaryId', 'principal',
                'kind', 'title', 'ownState', 'due', 'sourceRef'}
    if not isinstance(item, dict) or set(item) not in (required, required | {'identityBasis'}):
        raise ValueError('invalid_work_contract')
    for key in required - {'due', 'elementaryId'}:
        text(item[key])
    if not isinstance(item['elementaryId'], str) or len(item['elementaryId']) > 1000:
        raise ValueError('invalid_elementary_id')
    if item['kind'] not in {'task', 'meeting', 'reservation'} or item['ownState'] not in {'open', 'completed', 'cancelled'}:
        raise ValueError('unclassified_work')
    basis = item.get('identityBasis', 'elementaryActivity')
    if basis not in {'elementaryActivity', 'selfDiaryRecord'}:
        raise ValueError('invalid_identity_basis')
    if item['kind'] == 'task' and not item['elementaryId'] and basis != 'selfDiaryRecord':
        raise ValueError('own_elementary_required')
    if basis == 'selfDiaryRecord' and item['elementaryId']:
        raise ValueError('unexpected_elementary_identity')
    stamp(fetched_at)
    if item['due'] is not None:
        stamp(item['due'])
    identity = [item[k] for k in ('namespace', 'workspace', 'recordId', 'elementaryId', 'principal', 'kind')]
    work_id = digest(identity if basis == 'elementaryActivity' else [*identity, basis])
    payload_hash = digest(item)
    with transaction(db):
        old = db.execute('SELECT * FROM work_items WHERE namespace=? AND workspace=? AND record_id=? AND elementary_id=? AND principal=? AND kind=? AND identity_basis=?', (*identity, basis)).fetchone()
        if old:
            work_id = old['id']
        if old and stamp(fetched_at) < stamp(old['fetched_at']):
            raise ValueError('older_observation')
        if old and old['payload_hash'] == payload_hash:
            db.execute('UPDATE work_items SET fetched_at=? WHERE id=?', (fetched_at, work_id))
            return work_id
        version = old['revision'] + 1 if old else 1
        if old:
            db.execute('UPDATE work_items SET revision=?,source_state=?,payload_hash=?,fetched_at=?,preparation_state=? WHERE id=?',
                       (version, item['ownState'], payload_hash, fetched_at, 'needs_review', work_id))
        else:
            db.execute('INSERT INTO work_items VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)',
                       (work_id, *identity, version, item['ownState'], 'unprepared', payload_hash, fetched_at, basis))
        db.execute('INSERT INTO work_revisions VALUES (?,?,?,?,?)',
                   (work_id, version, canonical(item), payload_hash, fetched_at))
        db.execute('INSERT INTO audit_events(kind,subject,revision,at) VALUES (?,?,?,?)',
                   ('work_observed', work_id, version, fetched_at))
    return work_id


def add_step(db, work_id, step_key, outcome):
    text(step_key, 100)
    text(outcome, 2000)
    with transaction(db):
        db.execute('INSERT OR IGNORE INTO preparation_steps(id,work_id,step_key,outcome) VALUES (?,?,?,?)',
                   (digest([work_id, step_key]), work_id, step_key, outcome))


def admit(db, event, now):
    """Preview routing only. Never promotes a candidate or creates a work item.

    A linked source is already resolved by exact identity, never by title alone.
    There is deliberately no humanApproved flag or synthetic confirmation path.
    """
    required = {'eventKey', 'source', 'intent', 'workId', 'sourceRef', 'sourceHash'}
    if not isinstance(event, dict) or set(event) != required:
        raise ValueError('invalid_intake_contract')
    for key in required - {'workId'}:
        text(event[key], 1000)
    if event['source'] not in {'plus4u', 'signal_digest', 'legacy', 'document', 'human', 'internal'}:
        raise ValueError('unknown_source')
    if event['intent'] not in {'work', 'context', 'candidate', 'preparation', 'operation', 'archive'}:
        raise ValueError('unknown_intent')
    if len(event['sourceHash']) != 64 or any(c not in '0123456789abcdef' for c in event['sourceHash']):
        raise ValueError('invalid_source_hash')
    at = stamp(now)
    payload_hash = digest(event)
    old = db.execute('SELECT * FROM intake_events WHERE event_key=?', (event['eventKey'],)).fetchone()
    if old:
        if old['input_hash'] != payload_hash:
            raise ValueError('event_key_reused')
        return dict(old)
    work = None
    if event['workId'] is not None:
        text(event['workId'], 64)
        work = db.execute('SELECT * FROM work_items WHERE id=?', (event['workId'],)).fetchone()
        if not work:
            raise ValueError('unresolved_work_reference')
    intent = event['intent']
    if intent == 'archive':
        route, reason = 'archive', 'historical_list_not_active'
    elif intent == 'operation':
        route, reason = 'operations', 'not_personal_work'
    elif intent == 'preparation':
        if not work:
            raise ValueError('preparation_parent_required')
        route, reason = 'step', 'preparation_under_parent'
    elif intent == 'work' and event['source'] == 'plus4u' and work:
        if work['source_state'] != 'open':
            route, reason = 'archive', 'own_part_not_open'
        elif work['kind'] == 'task':
            route, reason = 'inbox', 'authoritative_own_task'
        else:
            route, reason = 'agenda', 'calendar_not_task'
    elif work:
        route, reason = 'enrich', 'linked_existing_work'
    elif intent == 'context':
        route, reason = 'knowledge', 'context_not_commitment'
    else:
        route, reason = 'review', 'needs_admission_review'
    # Proposed pilot retention, not a newly approved production policy.
    expires = (at + timedelta(days=14)).isoformat() if route == 'review' else None
    with transaction(db):
        db.execute('INSERT INTO intake_events VALUES (?,?,?,?,?,?,?,?,?)',
                   (event['eventKey'], payload_hash, canonical(event), route, reason, event['workId'], now, expires, 'open'))
    return dict(db.execute('SELECT * FROM intake_events WHERE event_key=?', (event['eventKey'],)).fetchone())


def expire_candidates(db, now):
    stamp(now)
    with transaction(db):
        return db.execute("UPDATE intake_events SET status='expired' WHERE route='review' AND status='open' AND julianday(expires_at)<=julianday(?)", (now,)).rowcount


def propose_claim(db, claim):
    """Append a sourced proposal. Cannot confirm a decision or assert current truth.

    Published Markdown and its rebuildable search index are a later integration.
    """
    required = {'topic', 'steward', 'kind', 'statement', 'sourceRef', 'sourceHash',
                'observedAt', 'validAsOf', 'reviewAfter', 'status', 'supersedes',
                'conflictsWith', 'workId'}
    if not isinstance(claim, dict) or set(claim) != required:
        raise ValueError('invalid_claim_contract')
    for key in required - {'supersedes', 'conflictsWith', 'workId'}:
        text(claim[key], 4000 if key == 'statement' else 1000)
    if claim['kind'] not in {'reported_fact', 'inference', 'decision_candidate', 'question'}:
        raise ValueError('confirmation_not_supported')
    if claim['status'] not in {'historical', 'unverified', 'conflicted'}:
        raise ValueError('verification_not_supported')
    if len(claim['sourceHash']) != 64 or any(c not in '0123456789abcdef' for c in claim['sourceHash']):
        raise ValueError('invalid_source_hash')
    observed = stamp(claim['observedAt'])
    stamp(claim['validAsOf'])
    if stamp(claim['reviewAfter']) < observed:
        raise ValueError('review_before_observation')
    for key in ('supersedes', 'conflictsWith'):
        if claim[key] is not None:
            text(claim[key], 64)
            row = db.execute('SELECT topic FROM knowledge_claims WHERE id=?', (claim[key],)).fetchone()
            if not row or row['topic'] != claim['topic']:
                raise ValueError('unresolved_claim_reference')
    if claim['conflictsWith'] is not None and claim['status'] != 'conflicted':
        raise ValueError('conflict_not_disclosed')
    if claim['workId'] is not None:
        text(claim['workId'], 64)
        if not db.execute('SELECT 1 FROM work_items WHERE id=?', (claim['workId'],)).fetchone():
            raise ValueError('unresolved_work_reference')
    # Observation timestamps live in captures/source snapshots. Re-reading the
    # same sourced proposition must not create another knowledge proposition.
    claim_id = digest({k: v for k, v in claim.items() if k not in {'observedAt','validAsOf','reviewAfter'}})
    with transaction(db):
        db.execute('INSERT OR IGNORE INTO knowledge_claims VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
                   (claim_id, claim['topic'], claim['steward'], claim['kind'], claim['statement'],
                    claim['sourceRef'], claim['sourceHash'], claim['observedAt'], claim['validAsOf'],
                    claim['reviewAfter'], claim['status'], claim['supersedes'], claim['conflictsWith'], claim['workId']))
    return claim_id
