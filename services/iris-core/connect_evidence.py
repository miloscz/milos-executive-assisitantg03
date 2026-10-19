"""Fixed pilot adapter for approved, normalized IrisRead data.

No HTTP, credentials, arbitrary command, URL or caller-selected file inputs.
Native source validation and peer pairing remain in Iris Connect.
"""
from datetime import timedelta
import json
import re
import uuid
from urllib.parse import urlsplit, parse_qsl

import briefing
import evidence
import workflow

MEETING_RECORD = '6accc2634ec86aeb2dbdcab0'
TASK_RECORD = '6ac68a3bcd45c209a371a53c'
PILOT_DAY = '2026-10-19'
ALLOWED = {MEETING_RECORD, TASK_RECORD}
RECORD_FIELDS = {'id', 'name', 'description', 'contentTruncated', 'kind', 'startTime',
                 'endTime', 'showInDiary', 'activityState', 'ownElementaryState',
                 'activityType', 'sourceURL', 'rejected', 'cancelled'}


def safe_text(value, maximum):
    if not isinstance(value, str) or len(value) > maximum:
        raise ValueError('invalid_source_text')
    # Fail closed instead of persisting content that may contain secret values.
    if re.search(r'Bearer\s+|(?:authorization|cookie|access[_ -]?token|refresh[_ -]?token|client[_ -]?secret|accessCode[12]|AC[12])["\']?\s*[:=]|\bsk-[A-Za-z0-9_-]{16,}|\beyJ[A-Za-z0-9_-]{20,}\.', value, re.I):
        raise ValueError('sensitive_source_content')
    if any(ord(c) < 32 and c not in '\t\n\r' for c in value):
        raise ValueError('invalid_source_text')
    return value


def source_ref(value):
    safe_text(value, 1000)
    u = urlsplit(value)
    query = parse_qsl(u.query)
    if (u.scheme != 'https' or u.netloc != 'uuapp.plus4u.net' or u.fragment
            or not re.fullmatch(r'/(?:uu-elementarymanagement-maing01|uu-managementkit-maing02)/[0-9a-f]{32}/(?:meetingDetail|meeting|document|keyTask|request)', u.path)
            or len(query) != 1 or query[0][0] != ('id' if u.path.endswith('/meetingDetail') else 'oid')
            or not re.fullmatch(r'[0-9a-f]{24}', query[0][1])):
        raise ValueError('invalid_source_reference')
    return value


def validate_batch(batch, operation, now):
    if (not isinstance(batch, dict) or batch.get('operation') != operation or batch.get('scope') != 'self'
            or batch.get('complete') is not True or batch.get('contractVerified') is not True
            or batch.get('stale') is not False or not isinstance(batch.get('records'), list)
            or len(batch['records']) > 10000):
        raise ValueError('unverified_batch')
    age = evidence.stamp(now) - evidence.stamp(batch['fetchedAt'])
    if age < timedelta(seconds=-30) or age > timedelta(minutes=30):
        raise ValueError('stale_batch')
    ids = set()
    for record in batch['records']:
        if not isinstance(record, dict) or not set(record).issubset(RECORD_FIELDS):
            raise ValueError('unknown_record_field')
        identifier = evidence.text(record.get('id'), 256)
        if identifier in ids:
            raise ValueError('duplicate_record')
        ids.add(identifier)


def normalize(record, native_event):
    # The argument is now a native stable binding reference, never a session ID.
    if not isinstance(native_event, str) or not re.fullmatch(r'[0-9a-f]{64}', native_event):
        raise ValueError('bindingRequired')
    scope = 'native-self-binding:' + native_event
    if record['id'] not in ALLOWED:
        raise ValueError('outside_pilot')
    for key, limit in [('name', 1000), ('description', 32768)]:
        safe_text(record.get(key, ''), limit)
    if type(record.get('cancelled')) is not bool or (record.get('rejected') is not None and type(record['rejected']) is not bool):
        raise ValueError('unclassified_record')
    own = record.get('ownElementaryState')
    if own in briefing.PENDING:
        state = 'open'
    elif own in {'yesActive', 'solvedActive', 'completed'}:
        state = 'completed'
    elif own == 'cancelled':
        state = 'cancelled'
    else:
        raise ValueError('unknown_own_state')
    kind = 'task'
    if record['id'] == MEETING_RECORD:
        if record.get('activityType') != 'reserveTime' or record.get('kind') != 'reservationOrInvitation':
            raise ValueError('unclassified_record')
        kind = 'meeting'  # Content link confirms meeting; no permission to move it.
    elif record.get('activityType') not in {'doIt', 'decide', 'milestone'}:
        raise ValueError('unclassified_record')
    if record['cancelled'] or record.get('rejected') is True:
        raise ValueError('inactive_record_requires_review')
    return dict(namespace='iris-connect:uuDwRecord', workspace=scope, recordId=record['id'],
                elementaryId='', identityBasis='selfDiaryRecord', principal='native-confirmed-self',
                kind=kind, title=safe_text(record['name'], 1000), ownState=state,
                due=record.get('endTime'), sourceRef=source_ref(record.get('sourceURL')))


def fetch_native(calibrate=False):
    before = workflow.access()
    if not before['enabled']:
        raise ValueError('pairingRequired')
    if before['busy'] or not before['sessionValid']:
        raise ValueError('loginRequired')
    binding = workflow.helper('IrisRead', 'status')
    reference = checked_binding(binding)
    if calibrate:
        boundary = workflow.helper('IrisRead', 'diagnostics.calendarBoundaries')
        if boundary.get('verified') is not True:
            raise ValueError('contractPending')
        workflow.helper('IrisRead', 'diagnostics.sources')
    active = workflow.helper('IrisRead', 'tasks.listActive')
    calendar = workflow.helper('IrisRead', 'calendar.list', PILOT_DAY, PILOT_DAY)
    sources = workflow.helper('IrisRead', 'sources.prepare')
    after = workflow.access()
    if not after['sessionValid'] or after['event'] != before['event']:
        raise ValueError('native_epoch_changed')
    if checked_binding(workflow.helper('IrisRead', 'status')) != reference:
        raise ValueError('scopeReviewRequired')
    return {'event': before['event'], 'bindingRef': reference,
            'previousBindingRef': binding.get('previousBindingRef'),
            'active': active, 'calendar': calendar, 'sources': sources}


def checked_binding(value):
    ref = value.get('bindingRef')
    if (value.get('ok') is not True or value.get('paired') is not True or value.get('loginRequired') is not False
            or value.get('policy') != 'iris-connect-read-v1' or not isinstance(ref, str)
            or not re.fullmatch(r'[0-9a-f]{64}', ref)):
        raise ValueError('bindingRequired')
    return ref


def select_capture(value, now, day=PILOT_DAY):
    uuid.UUID(value['event'])
    reference = value.get('bindingRef')
    if not isinstance(reference, str) or not re.fullmatch(r'[0-9a-f]{64}', reference):
        raise ValueError('bindingRequired')
    for name in ('active', 'calendar', 'sources'):
        if value[name].get('bindingRef') != reference:
            raise ValueError('scopeReviewRequired')
    validate_batch(value['active'], 'tasks.listActive', now)
    validate_batch(value['calendar'], 'calendar.list', now)
    if value['calendar'].get('dateWindow') != {'dateFrom': day, 'dateTo': day, 'timezone': 'Europe/Prague'}:
        raise ValueError('wrong_calendar_window')
    source = value['sources']
    if (source.get('ok') is not True or source.get('policy') != 'iris-connect-briefing-sources-v1'
            or not isinstance(source.get('materials'), list) or type(source.get('complete')) is not bool):
        raise ValueError('unverified_sources')
    age = evidence.stamp(now) - evidence.stamp(source['fetchedAt'])
    if not timedelta(seconds=-30) <= age <= timedelta(minutes=30):
        raise ValueError('stale_batch')
    active = {r['id']: r for r in value['active']['records'] if r['id'] in ALLOWED}
    calendar = [r for r in value['calendar']['records'] if r['id'] == MEETING_RECORD]
    if set(active) != ALLOWED or len(calendar) != 1:
        raise ValueError('pilot_record_missing')
    meeting = calendar[0]
    # Calendar owns the observed time, not the older active-list time.
    active[MEETING_RECORD] = dict(active[MEETING_RECORD], startTime=meeting['startTime'], endTime=meeting['endTime'])
    for r in active.values():
        normalize(r, reference)
    if source_ref(meeting['sourceURL']) != active[MEETING_RECORD]['sourceURL']:
        raise ValueError('meeting_identity_changed')
    expected = '/uu-elementarymanagement-maing01/76cc9f8077b44b43b90c3542bd257b55/meetingDetail'
    u = urlsplit(meeting['sourceURL'])
    if u.path != expected or dict(parse_qsl(u.query)) != {'id': '6accc261794626a48995763f'}:
        raise ValueError('meeting_identity_changed')
    if evidence.stamp(meeting['endTime']) <= evidence.stamp(meeting['startTime']):
        raise ValueError('invalid_meeting_time')
    if len(source['materials']) > 64:
        raise ValueError('source_budget')
    materials = []
    for m in source['materials']:
        if m.get('recordId') not in ALLOWED or m.get('parentSourceURL'):
            continue
        ref = source_ref(m['sourceURL'])
        if ref != active[m['recordId']]['sourceURL'] or type(m.get('complete')) is not bool:
            raise ValueError('source_identity_mismatch')
        pages = []
        if not isinstance(m.get('pages'), list) or len(m['pages']) > 16:
            raise ValueError('source_budget')
        for p in m.get('pages', []):
            pages.append({'pageId': evidence.text(p['pageId'], 256), 'text': safe_text(p['text'], 100000), 'complete': p['complete'] is True})
        material_age = evidence.stamp(now) - evidence.stamp(m['fetchedAt'])
        if not timedelta(seconds=-30) <= material_age <= timedelta(minutes=30):
            raise ValueError('stale_batch')
        materials.append(dict(recordId=m['recordId'], sourceURL=ref, fetchedAt=m['fetchedAt'],
                              complete=m['complete'], preparationText=safe_text(m.get('preparationText', ''), 100000),
                              minutesText=safe_text(m.get('minutesText', ''), 100000), pages=pages))
    if not any(m['recordId'] == MEETING_RECORD and m['preparationText'] for m in materials):
        raise ValueError('meeting_content_missing')
    return {'event': value['event'], 'bindingRef': reference, 'previousBindingRef': value.get('previousBindingRef'),
            'date': day, 'activeAt': value['active']['fetchedAt'],
            'calendarAt': value['calendar']['fetchedAt'], 'sourcesAt': source['fetchedAt'],
            'records': [active[k] for k in sorted(active)], 'materials': materials,
            'sourceBatchComplete': source['complete']}


def ingest(store, capture, now):
    db = store.db
    epoch = capture['event']
    reference = capture['bindingRef']
    pinned = db.execute("SELECT value FROM store_meta WHERE key='binding_ref'").fetchone()
    if pinned and pinned[0] != reference:
        raise ValueError('scopeReviewRequired')
    content = {k: capture[k] for k in ('records', 'materials')}
    # Strip only observation times; changed content creates a new revision.
    content['materials'] = [{k: v for k, v in m.items() if k != 'fetchedAt'} for m in capture['materials']]
    content_hash = evidence.digest(content)
    capture_id = evidence.digest([reference, epoch, capture['activeAt'], capture['calendarAt'], capture['sourcesAt'], content_hash])
    known = db.execute('SELECT report FROM captures WHERE id=?', (capture_id,)).fetchone()
    if known:
        return json.loads(known[0])
    nested = db.in_transaction
    db.execute('SAVEPOINT native_capture' if nested else 'BEGIN IMMEDIATE')
    try:
        if not pinned:
            old = db.execute("SELECT value FROM store_meta WHERE key='native_epoch'").fetchone()
            if old:
                verified = db.execute("SELECT value FROM store_meta WHERE key='legacy_scope_verified'").fetchone()
                if capture.get('previousBindingRef') != reference or not verified or verified[0] != old[0]:
                    raise ValueError('scopeReviewRequired')
                old_scope = 'native-self-epoch:' + evidence.digest(old[0])
                # Preserve IDs and all foreign-key history; only the verified
                # scope changes. Upsert resolves the stable identity to this ID.
                rows = db.execute('SELECT * FROM work_items').fetchall()
                if any(r['workspace'] != old_scope or r['namespace'] != 'iris-connect:uuDwRecord' for r in rows):
                    raise ValueError('scopeReviewRequired')
                db.execute('UPDATE work_items SET workspace=? WHERE workspace=?', ('native-self-binding:' + reference, old_scope))
                db.execute('INSERT INTO audit_events(kind,subject,at) VALUES (?,?,?)', ('stable_binding_adopted', reference, now))
            db.execute("INSERT INTO store_meta VALUES ('binding_ref',?)", (reference,))
        db.execute("INSERT OR IGNORE INTO store_meta VALUES ('native_epoch',?)", (epoch,))
        mapped = {}
        for r in capture['records']:
            normalized = normalize(r, reference)
            fetched = capture['calendarAt'] if r['id'] == MEETING_RECORD else capture['activeAt']
            work = evidence.upsert_work(db, normalized, fetched)
            mapped[r['id']] = work
            raw_hash = evidence.digest(r)
            db.execute('INSERT OR IGNORE INTO source_snapshots VALUES (?,?,?,?)',
                       (raw_hash, normalized['sourceRef'], fetched, evidence.canonical(r)))
            evidence.admit(db, dict(eventKey='native:' + evidence.digest([work, raw_hash]), source='plus4u',
                                   intent='work', workId=work, sourceRef=normalized['sourceRef'], sourceHash=raw_hash), now)
        for material in capture['materials']:
            h = evidence.digest({k: v for k, v in material.items() if k != 'fetchedAt'})
            db.execute('INSERT OR IGNORE INTO source_snapshots VALUES (?,?,?,?)',
                       (h, material['sourceURL'], material['fetchedAt'], evidence.canonical(material)))
        evidence.add_step(db, mapped[MEETING_RECORD], 'decision-memo', 'Podklad k mobilnímu klientovi: varianty, zdroje, nejistoty a požadovaná rozhodnutí.')
        evidence.add_step(db, mapped[TASK_RECORD], 'verify-deliverable', 'Ověřit kritéria lokálního přepisu, identifikace řečníků a volby lokální/cloud; doložit chybějící výstup.')
        report = dict(id=capture_id, bindingRef=reference, contentHash=content_hash, capturedAt=now, activeAt=capture['activeAt'],
                      calendarAt=capture['calendarAt'], sourcesAt=capture['sourcesAt'],
                      mapped=mapped, sourceBatchComplete=capture['sourceBatchComplete'])
        db.execute('INSERT INTO captures VALUES (?,?,?,?,?,?,?,?)', (capture_id, now, epoch,
                   capture['activeAt'], capture['calendarAt'], capture['sourcesAt'], content_hash, evidence.canonical(report)))
        db.execute('RELEASE native_capture') if nested else db.commit()
        return report
    except BaseException:
        if nested:
            db.execute('ROLLBACK TO native_capture')
            db.execute('RELEASE native_capture')
        else:
            db.rollback()
        raise
