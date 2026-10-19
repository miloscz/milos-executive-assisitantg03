#!/usr/bin/env python3
"""Read-only, aggregate inventory of a fixed set of legacy business notes.

Never walks authentication directories, logs, recordings, or raw message archives.
No note bodies, names, URLs or extracted task text are emitted.
"""
import json
import os
from pathlib import Path
import re
from collections import Counter
from datetime import datetime, timezone

ROOT = Path('/Users/milosvodrazka/Personal/milos_executive_assistant')
AREAS = ('01-strategy', '04-production', '06-management', '_templates',
         'decisions', 'journal', 'me', 'meetings', 'messages', 'orgs', 'people',
         'product', 'products', 'projects', 'reports', 'tasks', 'topics')


def files(area):
    base = ROOT / 'vault' / area
    if base.is_symlink() or not base.is_dir():
        return
    for folder, dirs, names in os.walk(base, followlinks=False):
        dirs[:] = sorted(d for d in dirs if not d.startswith('.') and
                         not (Path(folder) / d).is_symlink())
        for name in sorted(names):
            p = Path(folder) / name
            if not name.startswith('.') and not p.is_symlink() and p.is_file():
                yield p


def note(p):
    if p.suffix != '.md' or p.stat().st_size > 1024 * 1024:
        return ''
    return p.read_text(encoding='utf-8', errors='replace')


def inventory():
    areas = []
    for area in AREAS:
        paths = list(files(area))
        stats = dict(area=area, files=len(paths), extensions=dict(Counter(p.suffix for p in paths)),
                     markdown=0, frontmatter=0, updatedDate=0, sourceField=0, stubTrue=0)
        for p in paths:
            t = note(p)
            if not t:
                continue
            parts = t.split('---', 2)
            fm = parts[1] if t.startswith('---\n') and len(parts) == 3 else ''
            stats['markdown'] += 1
            stats['frontmatter'] += bool(fm)
            stats['updatedDate'] += bool(re.search(r'^updated:\s*\d{4}-\d{2}-\d{2}', fm, re.M))
            stats['sourceField'] += bool(re.search(r'^source(?:_url)?:', fm, re.M))
            stats['stubTrue'] += bool(re.search(r'^stub:\s*true', fm, re.M))
        areas.append(stats)
    lists = []
    for name in ('inbox', 'next-actions', 'waiting-for', 'week', 'someday', 'done-log', 'recurring', 'key-tasks'):
        p = ROOT / 'vault/tasks' / (name + '.md')
        if p.is_symlink():
            continue
        text = note(p)
        opened = [s for s in text.splitlines() if re.match(r'^\s*- \[ \]', s)]
        sources = Counter()
        for s in opened:
            kind = ('signal' if '@source(signal:' in s else
                    'plus4u_url' if re.search(r'@source\(https://[^)]*(?:plus4u|unicorn)', s)
                    else 'other_or_missing_source')
            sources[kind] += 1
        lists.append(dict(name=name, open=len(opened), checked=len(re.findall(r'^\s*- \[[xX]\]', text, re.M)),
                          bySource=dict(sources), withDue=sum('@due(' in s for s in opened),
                          withOwner=sum('@owner(' in s for s in opened)))
    return dict(schemaVersion=1, observedAt=datetime.now(timezone.utc).isoformat(),
                scope='fixed_legacy_business_vault_aggregate_only', areas=areas, taskLists=lists)


if __name__ == '__main__':
    print(json.dumps(inventory(), ensure_ascii=False, indent=2))
