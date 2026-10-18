"""Bounded source-grounded context; source text is data, never instructions."""
from datetime import date
from pathlib import Path
import re
import unicodedata
from urllib.parse import urlsplit

LEGACY_MEETINGS = Path('/Users/milosvodrazka/Personal/milos_executive_assistant/vault/meetings')


def normalized(value):
    value = unicodedata.normalize('NFKD', value).encode('ascii', 'ignore').decode().lower()
    return ' '.join(re.findall(r'[a-z0-9]+', value))


def history_for(schedule, target, plain, safe_source):
    """Only selected meeting notes: same title AND source application workspace.

    No transcripts, auth folders, arbitrary caller paths or network requests.
    Historical series context is never represented as the current instance.
    """
    wanted = {}
    for row in schedule:
        u = urlsplit(row.get('sourceURL', ''))
        if u.hostname == 'uuapp.plus4u.net':
            wanted[(normalized(row['title']), u.path)] = row['id']
    found = {}
    paths = list(LEGACY_MEETINGS.glob('20??/??/*.md'))
    if len(paths) > 5000:
        return {}
    for path in paths:
        if path.is_symlink() or not path.is_file() or path.stat().st_size > 65536:
            continue
        if not path.resolve().is_relative_to(LEGACY_MEETINGS.resolve()):
            continue
        try:
            text = path.read_text()
        except (OSError, UnicodeError):
            continue
        if re.search(r'^stub:\s*true\s*$', text, re.M):
            continue
        when = re.search(r'^date:\s*(\d{4}-\d{2}-\d{2})\s*$', text, re.M)
        url = re.search(r'^source:\s*"?(https://[^\s"\n]+)', text, re.M)
        title = re.search(r'^#\s+\d{4}-\d{2}-\d{2}\s*[—–-]\s*(.+)$', text, re.M)
        if not (when and url and title):
            continue
        try:
            day = date.fromisoformat(when[1])
        except ValueError:
            continue
        if not 0 < (target - day).days <= 90 or not safe_source({'sourceURL': url[1]}):
            continue
        key = (normalized(title[1]), urlsplit(url[1]).path)
        identifier = wanted.get(key)
        if not identifier or found.get(identifier, {}).get('date', '') >= when[1]:
            continue
        # Prefer explicit minutes; otherwise retain the old agenda as context.
        body = re.split(r'^## (?:Minutes summary|Prep / agenda[^\n]*)\s*$', text, flags=re.M)
        extract = body[-1].split('\n## ')[0] if len(body) > 1 else text.split('\n\n', 2)[-1]
        found[identifier] = {'date': when[1], 'text': plain(extract, 600),
                             'sourceURL': url[1], 'label': plain(path.name, 140)}
    return found


def cards_for(briefing, active, historical, sources, plain):
    by_id = {r['id']: r for r in active['records']}
    cards = []
    rows = [('decision' if p['decisionNeeded'] else 'task', p) for p in briefing['priorities']]
    rows += [('meeting', p) for p in briefing['schedule']]
    seen = set()
    for kind, item in rows:
        if item['id'] in seen:
            continue
        seen.add(item['id'])
        record = by_id.get(item['id'], {})
        desc = plain(record.get('description'), 500)
        source = sources.get(item['id']) or sources.get(item.get('sourceURL'))
        old = historical.get(item['id'])
        facts = []
        if desc:
            facts.append('Popis v aktuálním DW: ' + desc)
        if source:
            if source.get('preparationText'):
                facts.append('Načtený zdroj (zatím bez obsahové analýzy): ' + plain(source['preparationText'], 1100))
            if source.get('minutesText'):
                facts.append('Zápis v aktuálním zdroji: ' + plain(source['minutesText'], 600))
        if old:
            facts.append('Historický kontext stejné řady, ' + old['date'] + ' (není potvrzením aktuálního stavu): ' + old['text'])
        if kind == 'meeting':
            missing = [] if source and source.get('complete') and source.get('preparationText') else ['Aktuální agenda a požadované výsledky schůzky.']
            questions = ['Co je dnes potřeba rozhodnout a jaký má být výstup?']
            if old:
                questions.append('Které otevřené body z minulého zápisu už byly vyřešené?')
            step = 'Projednat cíl, otevřené body a potřebná rozhodnutí; nevyvozovat přesunutelnost ze samotného kalendáře.'
        else:
            missing = ['Obsahová analýza podkladů a ověření kritérií rozhodnutí.'] if source else ['Aktuální zdrojový dokument a podklady ke splnění kritérií.']
            questions = ['Co konkrétně brání dokončení nebo rozhodnutí?', 'Jaký podklad musíme doplnit před schválením?']
            step = 'Připravit doložené varianty po načtení zdroje; bez podkladu nevydávat doporučení ke schválení.'
        if source and not source.get('complete'):
            missing.append('Část zdroje nebyla načtená nebo obsahuje nepodporovaný vložený obsah či přílohy.')
        cards.append({'id': item['id'], 'kind': kind, 'readiness': 'sourcesLoaded' if source and source.get('preparationText') else 'contextOnly',
                      'context': plain(' '.join(facts), 1800) or 'K dispozici je pouze název a termín; obsahový podklad chybí.',
                      'questions': questions, 'missing': missing, 'nextStep': step, 'evidence': [],
                      **({'historicalDate': old['date'], 'historicalSourceURL': old['sourceURL']} if old else {})})
    return cards[:14]
