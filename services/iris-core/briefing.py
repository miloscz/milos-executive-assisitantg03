#!/usr/bin/env python3
"""First local briefing compiler. Only the signed IrisRead can access business data.

No authentication, arbitrary URL, arbitrary file argument, calendar write or MFA.
Private runtime artifacts are never part of Git or exposed as general MCP files.
"""
import argparse
from datetime import datetime, timedelta, time, timezone
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
from urllib.parse import urlsplit, parse_qsl
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parents[2]
RUNTIME = ROOT / '.iris-runtime'
PRAGUE = ZoneInfo('Europe/Prague')
PENDING = {'initial', 'replanned', 'reactivated', 'attention', 'warning'}


def instant(value):
    if not isinstance(value, str) or len(value) > 40:
        raise ValueError('invalid_time')
    result = datetime.fromisoformat(value.replace('Z', '+00:00'))
    if result.tzinfo is None:
        raise ValueError('ambiguous_time')
    return result


def wire(value):
    return value.astimezone(timezone.utc).isoformat().replace('+00:00', 'Z')


def plain(value, maximum=800):
    if not isinstance(value, str):
        return ''
    value = re.sub(r'<[^>]*>', ' ', value)
    value = re.sub(r'[\x00-\x1f\x7f]', ' ', value)
    value = re.sub(r'\bsk-[A-Za-z0-9_-]{16,}|\beyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+', '[odstraněno]', value)
    return ' '.join(value.split())[:maximum]


def source(record):
    value = record.get('sourceURL')
    if not isinstance(value, str) or len(value) > 1000:
        return {}
    u = urlsplit(value)
    if (u.scheme != 'https' or u.hostname != 'uuapp.plus4u.net' or u.username or u.password or u.fragment
            or any(k not in {'id', 'oid', 'code', 'bid'} for k, _ in parse_qsl(u.query))):
        return {}
    return {'sourceURL': value}


def usable(record):
    return not record.get('cancelled') and record.get('rejected') is not True


def compile_briefing(active, calendar, target, now):
    if (active.get('operation') != 'tasks.listActive' or active.get('scope') != 'self'
            or active.get('complete') is not True or active.get('contractVerified') is not True
            or not isinstance(active.get('records'), list) or len(active['records']) > 10000):
        raise ValueError('incomplete_active_records')
    start = datetime.combine(target, time.min, PRAGUE)
    end = datetime.combine(target + timedelta(days=1), time.min, PRAGUE)
    covered = bool(calendar and calendar.get('operation') == 'calendar.list' and calendar.get('scope') == 'self'
                   and calendar.get('complete') is True and calendar.get('contractVerified') is True
                   and calendar.get('dateWindow', {}).get('dateFrom') == target.isoformat()
                   and calendar.get('dateWindow', {}).get('dateTo') == target.isoformat())
    rows = calendar['records'] if covered else active['records']
    schedule = []
    for r in rows:
        if not usable(r) or (r.get('showInDiary') or '').lower() not in {'timeblock', 'dayblock'}:
            continue
        try:
            a, b = instant(r.get('startTime')), instant(r.get('endTime'))
        except (ValueError, TypeError):
            covered = False
            continue
        if not (a < end and b > start and b > a):
            continue
        # The source does not prove participation, ownership or permission to move it.
        schedule.append({'id': plain(r['id'], 256), 'title': plain(r.get('name')) or 'Nepojmenovaný blok',
                         'start': wire(a), 'end': wire(b), **source(r)})
    schedule.sort(key=lambda r: (r['start'], r['end'], r['id']))
    conflicts = []
    for i, first in enumerate(schedule):
        for second in schedule[i+1:]:
            a = max(instant(first['start']), instant(second['start']))
            b = min(instant(first['end']), instant(second['end']))
            if a < b:
                conflicts.append({'start': wire(a), 'end': wire(b), 'titles': [first['title'], second['title']]})
    linked = {r.get('sourceURL') for r in schedule if r.get('sourceURL')}
    candidates = []
    for r in active['records']:
        if not usable(r) or r.get('activityType') not in {'doIt', 'decide', 'milestone'} or r.get('ownElementaryState') not in PENDING:
            continue
        try:
            due = instant(r.get('endTime'))
        except (ValueError, TypeError):
            continue
        if not start - timedelta(days=7) <= due < end:
            continue
        is_linked = r.get('sourceURL') in linked
        decision = r.get('activityType') == 'decide'
        score = (100 if is_linked else 0) + (50 if decision else 0) + (20 if due >= start else 0)
        candidates.append((score, due, r, is_linked, decision))
    candidates.sort(key=lambda x: (-x[0], x[1], x[2]['id']))
    priorities = []
    for _, due, r, is_linked, decision in candidates[:3]:
        title = plain(r.get('name')) or 'Nepojmenovaná pracovní položka'
        desc = plain(r.get('description'), 220)
        if is_linked:
            meeting = next((s for s in schedule if s.get('sourceURL') == r.get('sourceURL')), None)
            if meeting: title = 'Příprava: ' + meeting['title']
        elif decision:
            phase = re.search(r'fáze\s+(uu[A-Za-z0-9]+\s+\d{4}/\dQ)', desc)
            if phase: title = 'Revize a schválení fáze ' + phase[1]
        why = ('Položka je propojená se zítřejším časovým blokem. ' if is_linked else '')
        why += ('Termín v +4U už uplynul; položka má stále otevřený vlastní stav.' if due < start else 'Termín v +4U připadá na tento den.')
        if decision:
            # No fabricated recommendation to approve a document we have not read.
            step = ('Připravit rozhodnutí: ověřit aktuální verzi zdrojového podkladu, splnění kritérií a otevřené výhrady. '
                    'Možnosti k projednání: schválit, vrátit s konkrétními připomínkami, nebo vyžádat chybějící podklad. '
                    'Doporučení ke schválení zatím není podložené.')
        elif is_linked:
            step = ('Před schůzkou připravit její cíl, potřebná rozhodnutí, stav předchozích závěrů a otevřené otázky. '
                    'Zdrojový detail schůzky zatím není načtený.')
        else:
            step = ('Ověřit aktuální stav a nejbližší konkrétní výstup. ' + desc) if desc else 'Ověřit aktuální stav a vyjasnit chybějící zadání před přípravou řešení.'
        priorities.append({'id': plain(r['id'], 256), 'title': title, 'due': wire(due), 'why': why,
                           'nextStep': step, 'decisionNeeded': decision, **source(r)})
    warnings = ['Jde o první přípravný briefing ze čtení +4U; detailní zdrojové dokumenty nejsou načtené. Nic nebylo schváleno, přesunuto ani zapsáno do inboxu.']
    if not covered:
        warnings.append('Kalendář není potvrzený jako úplný. Uvedené bloky pocházejí jen z aktivních DW záznamů; volný čas nelze potvrdit.')
    if len(schedule) > 24 or len(conflicts) > 8:
        warnings.append('Přehled je zkrácený; před plánováním otevři zdrojovou agendu.')
    stamp = instant(active['fetchedAt'])
    if covered:
        stamp = min(stamp, instant(calendar['fetchedAt']))
    if now - stamp > timedelta(minutes=30):
        warnings.append('Podklady jsou starší než 30 minut. Před ranním rozhodováním je potřeba nové čtení přes Iris.')
    def clock(value): return instant(value).astimezone(PRAGUE).strftime('%H:%M')
    summary = f'Briefing na {target.strftime("%d. %m. %Y")}. '
    summary += f'Ve zdrojových datech je {len(schedule)} časových bloků'
    if schedule:
        summary += f', první začíná v {clock(schedule[0]["start"])} a poslední končí v {clock(max(schedule,key=lambda r:r["end"])["end"])}'
    summary += '. '
    if conflicts:
        summary += 'Pozor na souběhy: ' + '; '.join(f'{clock(x["start"])} až {clock(x["end"])}: ' + ' a '.join(x['titles']) for x in conflicts[:3]) + '. '
    if priorities:
        summary += 'Nejdřív projdeme ' + '; '.join(p['title'] for p in priorities) + '. '
    summary += 'Žádný blok se zatím nerezervuje. Přesun společné schůzky musí projít tvým rozhodnutím a koordinací s Adélou.'
    if not covered:
        summary += ' Kalendář je zatím jen částečný; případnou mezeru nepovažuji za volný čas.'
    return {'schemaVersion': 1, 'date': target.isoformat(), 'timezone': 'Europe/Prague', 'generatedAt': wire(now),
            'sourceFetchedAt': wire(stamp), 'calendarCoverage': 'verified' if covered else 'activeRecordsOnly',
            'summary': summary, 'warnings': warnings, 'schedule': schedule[:24], 'priorities': priorities,
            'conflicts': conflicts[:8]}


def private_write(name, value):
    RUNTIME.mkdir(mode=0o700, exist_ok=True)
    if RUNTIME.is_symlink() or RUNTIME.stat().st_mode & 0o077:
        raise ValueError('unsafe_runtime_directory')
    fd, temp = tempfile.mkstemp(prefix='.briefing-', dir=RUNTIME)
    try:
        with os.fdopen(fd, 'w') as f:
            json.dump(value, f, ensure_ascii=False)
        os.replace(temp, RUNTIME / name)
    finally:
        if os.path.exists(temp): os.unlink(temp)


def read_native(operation, target=None):
    args = [str(ROOT / 'build/Iris Connect.app/Contents/MacOS/IrisRead'), operation]
    if target is not None: args += [target.isoformat(), target.isoformat()]
    result = subprocess.run(args, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                            env={'HOME': str(Path.home()), 'PATH': '/usr/bin:/bin'}, timeout=550)
    if len(result.stdout) > 52_428_800: raise ValueError('response_too_large')
    value = json.loads(result.stdout)
    if result.returncode or value.get('ok') is False: raise ValueError('native_read_unavailable')
    return value


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['build', 'refresh'])
    parser.add_argument('--date', required=True)
    args = parser.parse_args()
    target = datetime.strptime(args.date, '%Y-%m-%d').date()
    if target.isoformat() != args.date: raise ValueError('invalid_date')
    now = datetime.now(timezone.utc)
    if abs((target - now.astimezone(PRAGUE).date()).days) > 30: raise ValueError('date_out_of_range')
    if args.action == 'refresh':
        active = read_native('tasks.listActive'); private_write('active-records.json', active)
        try:
            calendar = read_native('calendar.list', target); private_write('calendar-records.json', calendar)
        except ValueError:
            calendar = None
    else:
        active = json.loads((RUNTIME / 'active-records.json').read_text())
        calendar = None
    briefing = compile_briefing(active, calendar, target, now)
    private_write('morning-briefing.json', briefing)
    print(json.dumps({'ok': True, 'date': briefing['date'], 'calendarCoverage': briefing['calendarCoverage'],
                      'blocks': len(briefing['schedule']), 'priorities': len(briefing['priorities']), 'conflicts': len(briefing['conflicts'])}))


if __name__ == '__main__':
    try: main()
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError):
        print('{"ok":false,"error":"briefing_preparation_failed"}'); raise SystemExit(1)
