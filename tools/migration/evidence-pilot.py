#!/usr/bin/env python3
"""Synthetic offline walkthrough. Does not read legacy or live runtime data."""
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'services/iris-core'))
import evidence

db = evidence.connect()
at = '2026-10-18T20:00:00Z'
task = dict(namespace='synthetic-plus4u', workspace='demo', recordId='task-a', elementaryId='own-a',
            principal='demo-owner', kind='task', title='Synthetic task', ownState='open', due=None,
            sourceRef='synthetic:task-a')
work = evidence.upsert_work(db, task, at)
evidence.upsert_work(db, task, at)
meeting = dict(task, recordId='meeting-a', elementaryId='', kind='meeting', sourceRef='synthetic:meeting-a')
parent = evidence.upsert_work(db, meeting, at)
evidence.add_step(db, parent, 'memo', 'Prepare a synthetic memo under the meeting')
cases = [('own_task', 'plus4u', 'work', work), ('meeting', 'plus4u', 'work', parent),
         ('related_message', 'signal_digest', 'candidate', parent),
         ('unassigned_message', 'signal_digest', 'candidate', None),
         ('historical_fact', 'legacy', 'context', None), ('overflow', 'internal', 'operation', None),
         ('old_inbox', 'legacy', 'archive', None), ('prep', 'internal', 'preparation', parent)]
out = []
for key, source, intent, target in cases:
    result = evidence.admit(db, dict(eventKey=key, source=source, intent=intent, workId=target,
                                   sourceRef='synthetic:' + key, sourceHash='a' * 64), at)
    out.append(dict(example=key, route=result['route'], reason=result['reason']))
print(json.dumps(dict(mode='synthetic_offline_only', outcomes=out,
                     workItems=db.execute('SELECT count(*) FROM work_items').fetchone()[0],
                     personalInbox=db.execute('SELECT count(*) FROM personal_inbox').fetchone()[0],
                     agenda=db.execute('SELECT count(*) FROM calendar_agenda').fetchone()[0]), indent=2))
db.close()
