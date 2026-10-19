#!/usr/bin/env python3
"""Human-authorized bounded shadow pilot. Fixed sources, no external writes."""
import argparse
from datetime import datetime, timedelta, timezone
import hashlib
import json
import os
from pathlib import Path
import stat

import briefing
import connect_evidence as adapter
import evidence
from private_store import Store

LEGACY = Path('/Users/milosvodrazka/Personal/milos_executive_assistant')
FILES = (
    'vault/messages/2026/10/2026-10-12-meetings-ai-records-mobile-app.md',
    'vault/messages/2026/10/2026-10-12-uso-pilot-nahravani-schuzek.md',
    'vault/decisions/2026-10-06-companion-local-transcription-models.md',
)


def legacy_read(relative):
    if relative not in FILES:
        raise ValueError('outside_legacy_pilot')
    fd = os.open(LEGACY, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        parts = Path(relative).parts
        for name in parts[:-1]:
            nxt = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            os.close(fd)
            fd = nxt
        source = os.open(parts[-1], os.O_RDONLY | os.O_NOFOLLOW, dir_fd=fd)
        with os.fdopen(source, 'rb') as handle:
            info = os.fstat(handle.fileno())
            if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid()
                    or info.st_nlink != 1 or info.st_size > 65536):
                raise ValueError('unsafe_legacy_source')
            raw = handle.read(65537)
            if len(raw) > 65536:
                raise ValueError('source_budget')
        text = adapter.safe_text(raw.decode('utf-8'), 65536)
        return dict(ref='legacy:' + relative, hash=hashlib.sha256(raw).hexdigest(), text=text)
    finally:
        os.close(fd)


def prepare_context(store, capture, mapping, now, legacy_sources):
    db = store.db
    meeting = next(r for r in capture['records'] if r['id'] == adapter.MEETING_RECORD)
    task = next(r for r in capture['records'] if r['id'] == adapter.TASK_RECORD)
    material = next(m for m in capture['materials'] if m['recordId'] == adapter.MEETING_RECORD)
    mobile, pilot, decision = legacy_sources
    # The curated extraction is bound to expected source wording. A changed note
    # needs a new content review instead of silently retaining an old conclusion.
    anchors = [(mobile, '19. 10. 11:00–12:00'), (mobile, 'USY Sales'),
               (pilot, 'stačí minutka'), (decision, 'STATUS: DRAFT'),
               (decision, 'awaiting Miloš')]
    if any(quote not in source['text'] for source, quote in anchors):
        raise ValueError('legacy_content_review_required')
    for source in legacy_sources:
        reviewed = {r[0] for r in db.execute('SELECT hash FROM source_snapshots WHERE source_ref=?', (source['ref'],))}
        if reviewed and source['hash'] not in reviewed:
            raise ValueError('legacy_content_review_required')
        db.execute('INSERT OR IGNORE INTO source_snapshots VALUES (?,?,?,?)',
                   (source['hash'], source['ref'], now, evidence.canonical({'text': source['text']})))
    review = (evidence.stamp(now) + timedelta(days=1)).isoformat()
    meeting_hash = evidence.digest(meeting)
    material_hash = evidence.digest({k: v for k, v in material.items() if k != 'fetchedAt'})
    start = evidence.stamp(meeting['startTime']).astimezone(briefing.PRAGUE)
    end = evidence.stamp(meeting['endTime']).astimezone(briefing.PRAGUE)
    claims = []

    def claim(kind, statement, ref, h, when, quote, status='historical', conflict=None):
        value = dict(topic='meeting-recording-companion', steward='iris-knowledge', kind=kind,
                     statement=statement, sourceRef=ref, sourceHash=h, observedAt=now,
                     validAsOf=when, reviewAfter=review, status=status, supersedes=None,
                     conflictsWith=conflict, workId=mapping[adapter.MEETING_RECORD])
        key = evidence.propose_claim(db, value)
        stored = db.execute('SELECT valid_as_of FROM knowledge_claims WHERE id=?', (key,)).fetchone()
        claims.append(dict(id=key, kind=kind, statement=statement, sourceRef=ref,
                           sourceHash=h, validAsOf=stored[0], status=status, quote=quote))
        return key

    current_time = claim('reported_fact', f'Načtený kalendář uvádí {start:%d. %m. %Y %H:%M}–{end:%H:%M} Europe/Prague.',
                         meeting['sourceURL'], meeting_hash, capture['calendarAt'],
                         {'start': meeting['startTime'], 'end': meeting['endTime']}, 'unverified')
    claim('reported_fact', 'Text přípravy stanoví cíl domluvit plán uvedení nahrávacího nástroje na Android a Apple marketplaces; nejde o potvrzení realizace.',
          material['sourceURL'], material_hash, material['fetchedAt'], material['preparationText'], 'unverified')
    differs = (start.hour, start.minute, end.hour, end.minute) != (11, 0, 12, 0)
    claim('reported_fact', 'Historický digest z 12. října uvádí pro schůzku 19. října čas 11:00–12:00; pro dnešní agendu má přednost čerstvý kalendář.',
          mobile['ref'], mobile['hash'], '2026-10-12T00:00:00+02:00', '19. 10. 11:00–12:00',
          'conflicted' if differs else 'historical', current_time if differs else None)
    claim('reported_fact', 'Historický digest hlásí poptávku USY Sales po mobilním klientovi; původní Signal se v tomto pilotu neověřoval.',
          mobile['ref'], mobile['hash'], '2026-10-12T00:00:00+02:00', 'USY Sales')
    claim('inference', 'Před závazkem k mobilním platformám doporučuji vyjasnit vlastníka, rozsah a kapacitu. Jde o návrh Iris.',
          mobile['ref'], mobile['hash'], '2026-10-12T00:00:00+02:00', 'USY Sales', 'unverified')
    claim('reported_fact', 'Historický pilotní digest cituje doporučení provést před ostrým nahráváním minutový test; aktuální stav návodu se neověřoval.',
          pilot['ref'], pilot['hash'], '2026-10-12T00:00:00+02:00', 'stačí minutka')
    claim('decision_candidate', 'Historický návrh lokálních modelů pro přepis je stále označený jako DRAFT; import nepotvrzuje Milošovo rozhodnutí.',
          decision['ref'], decision['hash'], '2026-10-06T00:00:00+02:00', 'STATUS: DRAFT')
    for source, intent, parent in [(mobile, 'context', mapping[adapter.MEETING_RECORD]),
                                   (pilot, 'context', None), (decision, 'candidate', None)]:
        evidence.admit(db, dict(eventKey='legacy:' + evidence.digest([source['ref'], source['hash']]),
                               source='legacy', intent=intent, workId=parent,
                               sourceRef=source['ref'], sourceHash=source['hash']), now)
    return dict(schemaVersion=1, pilot='meeting-recording', date=capture.get('date', adapter.PILOT_DAY),
                meetingStart=meeting['startTime'], meetingEnd=meeting['endTime'],
                preparedAt=now, calendarFetchedAt=capture['calendarAt'], claims=claims,
                historicalLink='curated_content_relation_not_system_identity',
                task=dict(id=task['id'], title=task['name'], description=task.get('description', ''),
                          due=task.get('endTime'), sourceRef=task['sourceURL'],
                          relation='related_theme_dependency_not_verified'),
                limits=['Podklady schůzky jsou úplné jen v rozsahu vráceném Iris Connect.',
                        'Znalosti ze starých digestů nejsou ověřené proti původnímu Signalu.',
                        'Nebylo ověřeno, že existuje hotový výstup úkolu s lokálními přepisy.'])


def memo(context, capture):
    return dict(schemaVersion=1, preparedAt=context['preparedAt'],
                sourceCaptureHash=evidence.digest(capture), status='proposal_partial',
                title='Meetings AI records tool – rozhodovací podklad',
                objective='Vyjasnit další postup pro mobilní nahrávání, odpovědnost a podmínky pilotu bez nepodloženého termínu dodání.',
                options=[
                    {'option': 'Nejdřív ověřovací pilot', 'benefit': 'Zjistíme potřebné funkce a omezení před závazkem k oběma platformám.', 'cost': 'Vyžaduje vlastníka a omezenou kapacitu pro ověření.'},
                    {'option': 'Samostatný mobilní klient nad společným backendem', 'benefit': 'Jasné rozdělení odpovědností je možné.', 'cost': 'Rozhraní, vlastník, rozpočet a mobilní omezení zatím nejsou doložené.'},
                    {'option': 'Odložit mobilní realizaci a vyjasnit návaznost na desktop', 'benefit': 'Chrání kapacitu pro již existující práci.', 'cost': 'Odkládá využití pro USY Sales; aktuální stav desktopu je nutné ověřit.'}
                ],
                recommendation='Na schůzce nejprve potvrdit vlastníka a konkrétní uživatelský scénář; teprve potom zvolit rozsah ověření. Jde o návrh Iris, ne uložené rozhodnutí.',
                humanQuestions=['Kdo odpovídá za mobilní klient a jeho rozpočet?',
                                'Jaký minimální scénář má pilot ověřit a kdo výsledek převezme?',
                                'Jaká kapacita je dostupná a jak se pilot vztahuje k úkolu lokálních přepisů?'],
                missing=['Doložený vlastník a kapacita mobilního řešení.',
                         'Aktuální ověření technických omezení mobilního nahrávání a distribuce.',
                         'Právní a provozní požadavky pro zvolený scénář nejsou těmito podklady ověřené.',
                         'Výstup a akceptační důkaz lokálních přepisů, nikoli jen text zadání.'],
                taskPreparation={'recordId': adapter.TASK_RECORD,
                                 'observedRequirement': context['task']['description'],
                                 'draftAcceptanceChecklist': ['Zkušební přepis se známými řečníky a popsaným vyhodnocením.',
                                                              'Doložená volba lokálního a cloudového režimu v uživatelském toku.',
                                                              'Popis omezení, chyb a nároků na hardware.'],
                                 'note': 'Návrh kontrolního seznamu; původní zadání jej zatím nepotvrdilo.'},
                humanTime={'proposedMinutes': 15, 'latestBefore': (evidence.stamp(context['meetingStart']).astimezone(briefing.PRAGUE) - timedelta(minutes=30)).isoformat(), 'calendarWrite': False},
                claimIds=[c['id'] for c in context['claims']], decisionsConfirmed=False)


def run_capture(store, raw, now):
    capture = adapter.select_capture(raw, now)
    # Read/review all fixed historical inputs before mutating the pilot database.
    sources = [legacy_read(p) for p in FILES]
    if not store.db.execute("SELECT 1 FROM store_meta WHERE key='binding_ref'").fetchone() and store.metadata()['workItems']:
        store.backup_check('prebinding.sqlite')
    store.db.execute('BEGIN IMMEDIATE')
    try:
        result = adapter.ingest(store, capture, now)
        context = prepare_context(store, capture, result['mapped'], now, sources)
        store.db.commit()
    except BaseException:
        store.db.rollback()
        raise
    store.write_json('pilot-context.json', context)
    proposal = memo(context, capture)
    store.write_json('pilot-memo.json', proposal)
    store.write_memo(render_memo(context, proposal))
    return result


def render_memo(context, proposal):
    lines = ['# ' + proposal['title'], '',
             'Stav: návrh k projednání, podklady jsou částečné. Nic nebylo schváleno ani zapsáno do +4U.', '',
             'Připraveno: ' + context['preparedAt'],
             'Kalendář skutečně načten: ' + context['calendarFetchedAt'], '',
             '## Cíl a doložený kontext', '', proposal['objective'], '']
    for c in context['claims']:
        lines += ['- **' + c['kind'] + ' / ' + c['status'] + ':** ' + c['statement'],
                  '  Zdroj: ' + c['sourceRef'] + '; datováno ' + c['validAsOf'] + '; SHA-256 ' + c['sourceHash'] + '.']
    lines += ['', '## Varianty k rozhodnutí', '']
    for option in proposal['options']:
        lines += ['- **' + option['option'] + ':** ' + option['benefit'] + ' ' + option['cost']]
    lines += ['', '## Návrh Iris', '', proposal['recommendation'], '', '## Otázky pro Miloše', '']
    lines += ['- ' + q for q in proposal['humanQuestions']]
    lines += ['', '## Co chybí', ''] + ['- ' + q for q in proposal['missing']]
    lines += ['', '## Samostatný úkol: lokální přepisy', '',
              context['task']['title'], '', 'Požadavek v načteném zadání: ' + context['task']['description'],
              '', 'Zdroj: ' + context['task']['sourceRef'],
              '', 'Termín z +4U: ' + str(context['task']['due']), '',
              proposal['taskPreparation']['note'], '']
    lines += ['- ' + q for q in proposal['taskPreparation']['draftAcceptanceChecklist']]
    lines += ['', '## Potřebný osobní čas', '',
              'Návrh: 15 minut před schůzkou, nejpozději ' + proposal['humanTime']['latestBefore'] + '. Čas není rezervovaný.', '',
              '## Omezení', ''] + ['- ' + q for q in context['limits']]
    return '\n'.join(lines) + '\n'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['run', 'status'])
    args = parser.parse_args()
    if args.action == 'status':
        with Store().locked() as store:
            print(json.dumps({'ok': True, **store.metadata()}))
        return
    results = []
    # Both operations independently go through the signed native helper. Native
    # caches keep their real fetchedAt; a cache hit is never called a new fetch.
    for attempt in range(2):
        raw = adapter.fetch_native(calibrate=attempt == 0)
        now = datetime.now(timezone.utc).isoformat()
        with Store().locked() as store:
            result = run_capture(store, raw, now)
            results.append(result)
            backup = store.backup_check()
    with Store().locked() as store:
        report = dict(ok=True, mode='live_read_only_shadow', completedAt=now,
                      attempts=2, distinctCaptures=len({r['id'] for r in results}),
                      repeatedContentEqual=results[0]['contentHash'] == results[1]['contentHash'],
                      sourceTimes=[{k: r[k] for k in ('activeAt','calendarAt','sourcesAt')} for r in results],
                      routes={r[0]: r[1] for r in store.db.execute('SELECT route,count(*) FROM intake_events GROUP BY route')},
                      backup=backup, originalIrisChanged=False, plus4uWrites=False,
                      aidaToolsChanged=False, **store.metadata())
        store.write_json('pilot-report.json', report)
        print(json.dumps(report))


if __name__ == '__main__':
    try:
        main()
    except BlockingIOError:
        print('{"ok":false,"error":"alreadyRunning"}')
    except Exception as exc:
        allowed = {'loginRequired','pairingRequired','bindingRequired','scopeReviewRequired','legacy_content_review_required',
                   'meeting_content_missing','stale_batch','pilot_record_missing','sensitive_source_content',
                   'contractPending','policyDenied','forbidden','httpFailure','deadline','rateLimited',
                   'schemaMismatch','responseTooLarge','cancelled','unstablePages','recordLimit','unavailable','transport'}
        code = str(exc) if type(exc) is ValueError and str(exc) in allowed else 'pilotUnavailable'
        print(json.dumps({'ok': False, 'error': code}))
        raise SystemExit(1)
