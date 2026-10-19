"""Bounded domain knowledge integrated into the ordinary briefing checkpoint.

Only the existing recording pilot is curated here. No general search, model
execution, arbitrary paths, URL fetch, credentials or human approvals.
"""
import briefing
import connect_evidence as adapter
import evidence
from private_store import Store
import recording_pilot


def sync(packet, event, binding, now):
    with Store(briefing.RUNTIME).locked() as store:
        pinned = store.db.execute("SELECT value FROM store_meta WHERE key='binding_ref'").fetchone()
        if pinned and pinned[0] != binding['bindingRef']:
            raise ValueError('scopeReviewRequired')
    ids = {r['id'] for r in (packet.get('calendar') or {}).get('records', [])}
    if adapter.MEETING_RECORD not in ids:
        return {'state': 'notRelevant', 'cards': [], 'details': []}
    raw = {k: packet[k] for k in ('active','calendar','sources')}
    raw.update(event=event, bindingRef=binding['bindingRef'], previousBindingRef=binding.get('previousBindingRef'))
    capture = adapter.select_capture(raw, now, day=packet['date'])
    legacy = [recording_pilot.legacy_read(p) for p in recording_pilot.FILES]
    with Store(briefing.RUNTIME).locked() as store:
        if not store.db.execute("SELECT 1 FROM store_meta WHERE key='binding_ref'").fetchone() and store.metadata()['workItems']:
            store.backup_check('prebinding.sqlite')
        store.db.execute('BEGIN IMMEDIATE')
        try:
            mapped = adapter.ingest(store, capture, now)['mapped']
            context = recording_pilot.prepare_context(store, capture, mapped, now, legacy)
            proposal = recording_pilot.memo(context, capture)
            store.db.commit()
        except BaseException:
            store.db.rollback()
            raise
        store.write_json('pilot-context.json', context)
        store.write_json('pilot-memo.json', proposal)
        store.write_memo(recording_pilot.render_memo(context, proposal))
        store.backup_check()
    return build(packet, context, proposal)


def build(packet, context, proposal):
    if context['date'] != packet['date']:
        raise ValueError('knowledge_date_mismatch')
    material = next((m for m in packet['sources']['materials'] if m['recordId'] == adapter.MEETING_RECORD and not m.get('parentSourceURL')), None)
    if not material:
        raise ValueError('meeting_content_missing')
    citations = []
    for page in material['pages']:
        text = briefing.plain(page['text'], 100000)
        quote = briefing.plain(material.get('preparationText', ''), 500)
        if len(quote) >= 16 and quote in text:
            citations.append(dict(sourceURL=material['sourceURL'], pageId=page['pageId'], quote=quote))
            break
    if not citations:
        raise ValueError('knowledge_quote_missing')
    historical = [c for c in context['claims'] if c['sourceRef'].startswith('legacy:')]
    facts = ' '.join(c['statement'] for c in historical if c['kind'] == 'reported_fact')
    options = ' '.join(o['option'] + ': ' + o['benefit'] + ' ' + o['cost'] for o in proposal['options'])
    body = ('Aktuální nativní příprava: ' + material['preparationText'] +
            ' Historické druhotné zdroje z 6. a 12. října, neověřené vůči původnímu Signalu: ' + facts +
            ' Varianty navržené Iris: ' + options)
    missing = ['Podklady jsou částečné; přílohy a další nepodporovaný obsah nejsou ověřené.',
               'Historické digesty nejsou ověřené proti původnímu Signalu. DRAFT není potvrzené rozhodnutí.',
               'Chybí potvrzený vlastník, kapacita a rozsah mobilního řešení.',
               'Splnění úkolu lokálních přepisů ani jeho procesní závislost na schůzce nejsou doložené.']
    card = dict(id=adapter.MEETING_RECORD, kind='meeting', readiness='prepared',
                context=briefing.plain(body, 1800), questions=proposal['humanQuestions'], missing=missing,
                nextStep=briefing.plain(proposal['recommendation'], 800), evidence=citations)
    sections = [dict(kind='overview', text=briefing.plain(material['preparationText'] + ' ' + facts, 1800)),
                dict(kind='options', text=briefing.plain(options, 1800)),
                dict(kind='recommendation', text=briefing.plain(proposal['recommendation'], 1800)),
                dict(kind='sources', text=briefing.plain(' '.join(
                    c['kind'] + ', ' + c['validAsOf'][:10] + ', ' + ('historický digest / návrh' if c['sourceRef'].startswith('legacy:') else 'aktuální +4U') + ': ' + c['statement']
                    for c in context['claims']), 1800)),
                dict(kind='task', text=briefing.plain(context['task']['title'] + ': ' + context['task']['description'] +
                    ' Návrh ověření, nikoli potvrzená akceptace: ' + ' '.join(proposal['taskPreparation']['draftAcceptanceChecklist']), 1800)),
                dict(kind='missing', text=briefing.plain(' '.join(missing), 1800))]
    detail = dict(id=adapter.MEETING_RECORD, title='Meetings AI records tool', readiness='partial',
                  sourceFetchedAt=packet['sources']['fetchedAt'], sections=sections, sources=citations, missing=missing)
    # No paths, binding refs, source snapshots, database handles or auth metadata
    # cross the publication boundary. Only these bounded prebuilt sections.
    return {'state': 'preparedPartial', 'cards': [card], 'details': [detail]}
