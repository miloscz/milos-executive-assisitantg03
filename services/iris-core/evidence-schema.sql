-- Offline pilot schema, v1. No connection to live workflow.sqlite or MCP.
PRAGMA foreign_keys = ON;
CREATE TABLE IF NOT EXISTS schema_version (version INTEGER PRIMARY KEY CHECK (version = 1));
INSERT OR IGNORE INTO schema_version VALUES (1);
CREATE TABLE IF NOT EXISTS work_items (
    id TEXT PRIMARY KEY,
    namespace TEXT NOT NULL,
    workspace TEXT NOT NULL,
    record_id TEXT NOT NULL,
    elementary_id TEXT NOT NULL,
    principal TEXT NOT NULL,
    kind TEXT NOT NULL CHECK (kind IN ('task','meeting','reservation')),
    revision INTEGER NOT NULL,
    source_state TEXT NOT NULL,
    preparation_state TEXT NOT NULL DEFAULT 'unprepared',
    payload_hash TEXT NOT NULL,
    fetched_at TEXT NOT NULL,
    UNIQUE(namespace,workspace,record_id,elementary_id,principal,kind)
);
CREATE TABLE IF NOT EXISTS work_revisions (
    work_id TEXT NOT NULL REFERENCES work_items(id),
    revision INTEGER NOT NULL,
    payload TEXT NOT NULL,
    payload_hash TEXT NOT NULL,
    fetched_at TEXT NOT NULL,
    PRIMARY KEY(work_id,revision)
);
CREATE TABLE IF NOT EXISTS preparation_steps (
    id TEXT PRIMARY KEY,
    work_id TEXT NOT NULL REFERENCES work_items(id),
    step_key TEXT NOT NULL,
    outcome TEXT NOT NULL,
    state TEXT NOT NULL DEFAULT 'proposed',
    UNIQUE(work_id,step_key)
);
-- A record is a versioned claim, not an entire topic treated as equally true.
CREATE TABLE IF NOT EXISTS knowledge_claims (
    id TEXT PRIMARY KEY,
    topic TEXT NOT NULL,
    steward TEXT NOT NULL,
    claim_kind TEXT NOT NULL CHECK(claim_kind IN ('reported_fact','inference','decision_candidate','confirmed_decision','question')),
    statement TEXT NOT NULL,
    source_ref TEXT NOT NULL,
    source_hash TEXT NOT NULL,
    observed_at TEXT NOT NULL,
    valid_as_of TEXT NOT NULL,
    review_after TEXT NOT NULL,
    status TEXT NOT NULL CHECK(status IN ('historical','unverified','current','conflicted','superseded')),
    supersedes TEXT REFERENCES knowledge_claims(id),
    conflicts_with TEXT REFERENCES knowledge_claims(id),
    work_id TEXT REFERENCES work_items(id)
);
CREATE TABLE IF NOT EXISTS intake_events (
    event_key TEXT PRIMARY KEY,
    input_hash TEXT NOT NULL,
    payload TEXT NOT NULL,
    route TEXT NOT NULL CHECK(route IN ('inbox','agenda','enrich','knowledge','review','operations','archive','step')),
    reason TEXT NOT NULL,
    work_id TEXT REFERENCES work_items(id),
    created_at TEXT NOT NULL,
    expires_at TEXT,
    status TEXT NOT NULL DEFAULT 'open' CHECK(status IN ('open','expired'))
);
CREATE TABLE IF NOT EXISTS audit_events (
    seq INTEGER PRIMARY KEY AUTOINCREMENT,
    kind TEXT NOT NULL,
    subject TEXT NOT NULL,
    revision INTEGER,
    at TEXT NOT NULL
);
-- Only authoritative tasks, no candidates or internal preparation steps.
CREATE VIEW IF NOT EXISTS personal_inbox AS
    SELECT * FROM work_items WHERE kind='task' AND source_state='open';
CREATE VIEW IF NOT EXISTS calendar_agenda AS
    SELECT * FROM work_items WHERE kind IN ('meeting','reservation') AND source_state='open';
