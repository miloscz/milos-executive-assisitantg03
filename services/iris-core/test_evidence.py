from copy import deepcopy
import tempfile
from pathlib import Path
import unittest

import evidence

AT = '2026-10-18T20:00:00Z'


def item(kind='task'):
    return dict(namespace='synthetic-plus4u', workspace='workspace-a', recordId='record-a',
                elementaryId='own-a' if kind == 'task' else '', principal='synthetic-owner',
                kind=kind, title='Synthetic work', ownState='open', due=None,
                sourceRef='synthetic:work-a')


def event(key, source='signal_digest', intent='candidate', work=None):
    return dict(eventKey=key, source=source, intent=intent, workId=work,
                sourceRef='synthetic:source', sourceHash='a' * 64)


class EvidenceTests(unittest.TestCase):
    def setUp(self):
        self.db = evidence.connect()

    def tearDown(self):
        self.db.close()

    def count(self, table):
        return self.db.execute('SELECT count(*) FROM ' + table).fetchone()[0]

    def test_repeat_observation_and_changed_due_keep_one_identity_and_history(self):
        initial = item()
        work = evidence.upsert_work(self.db, initial, AT)
        evidence.upsert_work(self.db, initial, '2026-10-19T04:40:00Z')
        self.assertEqual(self.count('work_revisions'), 1)
        changed = deepcopy(initial)
        changed['due'] = '2026-10-21T10:00:00Z'
        self.assertEqual(evidence.upsert_work(self.db, changed, '2026-10-19T04:41:00Z'), work)
        self.assertEqual(self.count('work_items'), 1)
        self.assertEqual(self.count('work_revisions'), 2)
        self.assertEqual(self.db.execute('SELECT preparation_state FROM work_items').fetchone()[0], 'needs_review')
        with self.assertRaisesRegex(ValueError, 'older_observation'):
            evidence.upsert_work(self.db, initial, AT)

    def test_same_title_other_identity_is_not_merged(self):
        a = item()
        b = item()
        b['elementaryId'] = 'own-b'
        self.assertNotEqual(evidence.upsert_work(self.db, a, AT), evidence.upsert_work(self.db, b, AT))
        self.assertEqual(self.count('personal_inbox'), 2)

    def test_own_part_completion_and_empty_partial_batch(self):
        a = item()
        work = evidence.upsert_work(self.db, a, AT)
        # No observation means no state mutation; there is no close-absent method.
        for row in []:
            evidence.upsert_work(self.db, row, AT)
        self.assertEqual(self.count('personal_inbox'), 1)
        a['ownState'] = 'completed'
        evidence.upsert_work(self.db, a, '2026-10-19T04:41:00Z')
        self.assertEqual(self.count('personal_inbox'), 0)
        self.assertEqual(evidence.admit(self.db, event('finished', 'plus4u', 'work', work), AT)['route'], 'archive')

    def test_meeting_and_preparation_do_not_become_extra_tasks(self):
        work = evidence.upsert_work(self.db, item('meeting'), AT)
        evidence.add_step(self.db, work, 'memo', 'A synthetic decision memo')
        evidence.add_step(self.db, work, 'memo', 'A synthetic decision memo')
        self.assertEqual(self.count('preparation_steps'), 1)
        self.assertEqual(self.count('personal_inbox'), 0)
        self.assertEqual(self.count('calendar_agenda'), 1)
        self.assertEqual(evidence.admit(self.db, event('meeting', 'plus4u', 'work', work), AT)['route'], 'agenda')
        self.assertEqual(evidence.admit(self.db, event('step', 'internal', 'preparation', work), AT)['route'], 'step')

    def test_signal_enriches_known_work_but_cannot_create_a_personal_task(self):
        work = evidence.upsert_work(self.db, item('meeting'), AT)
        cases = [('linked', 'signal_digest', 'candidate', work, 'enrich'),
                 ('unknown', 'signal_digest', 'candidate', None, 'review'),
                 ('fact', 'document', 'context', None, 'knowledge'),
                 ('overflow', 'internal', 'operation', None, 'operations'),
                 ('old_inbox', 'legacy', 'archive', None, 'archive'),
                 ('untrusted_human_label', 'human', 'candidate', None, 'review')]
        for key, source, intent, parent, expected in cases:
            with self.subTest(key=key):
                self.assertEqual(evidence.admit(self.db, event(key, source, intent, parent), AT)['route'], expected)
        self.assertEqual(self.count('personal_inbox'), 0)

    def test_dedupe_and_expiry_never_promote_candidate(self):
        e = event('same-event')
        self.assertEqual(evidence.admit(self.db, e, AT), evidence.admit(self.db, e, AT))
        self.assertEqual(self.count('intake_events'), 1)
        e['intent'] = 'work'
        with self.assertRaisesRegex(ValueError, 'event_key_reused'):
            evidence.admit(self.db, e, AT)
        self.assertEqual(evidence.expire_candidates(self.db, '2026-11-02T20:00:00Z'), 1)
        self.assertEqual(self.count('personal_inbox'), 0)
        self.assertEqual(self.db.execute('SELECT route,status FROM intake_events').fetchone()[:], ('review', 'expired'))

    def test_unresolved_parent_invalid_contract_and_forged_approval_rejected(self):
        with self.assertRaises(ValueError):
            evidence.admit(self.db, event('bad-parent', work='missing'), AT)
        e = event('bad-approval')
        e['humanApproved'] = True
        with self.assertRaises(ValueError):
            evidence.admit(self.db, e, AT)
        a = item()
        a['elementaryId'] = ''
        with self.assertRaises(ValueError):
            evidence.upsert_work(self.db, a, AT)
        with self.assertRaises(ValueError):
            evidence.upsert_work(self.db, item(), '2026-10-18T20:00:00')

    def test_committed_state_survives_reopen(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'synthetic.sqlite'
            db = evidence.connect(path)
            work = evidence.upsert_work(db, item(), AT)
            evidence.admit(db, event('e', work=work), AT)
            db.close()
            db = evidence.connect(path)
            self.assertEqual(db.execute('SELECT count(*) FROM work_revisions').fetchone()[0], 1)
            self.assertEqual(db.execute('SELECT route FROM intake_events').fetchone()[0], 'enrich')
            db.close()

    def claim(self):
        return dict(topic='synthetic-recording', steward='iris-knowledge', kind='reported_fact',
                    statement='A historically reported synthetic fact.', sourceRef='synthetic:note',
                    sourceHash='a' * 64, observedAt=AT, validAsOf='2026-10-12T10:00:00Z',
                    reviewAfter='2026-10-19T07:00:00Z', status='historical',
                    supersedes=None, conflictsWith=None, workId=None)

    def test_claims_keep_provenance_conflicts_and_unconfirmed_decisions(self):
        a = self.claim()
        old = evidence.propose_claim(self.db, a)
        self.assertEqual(evidence.propose_claim(self.db, a), old)
        b = dict(a, statement='A different historical report.', sourceHash='b' * 64,
                 conflictsWith=old, status='conflicted')
        evidence.propose_claim(self.db, b)
        candidate = dict(a, kind='decision_candidate', statement='A proposed choice, not an approval.')
        evidence.propose_claim(self.db, candidate)
        self.assertEqual(self.count('knowledge_claims'), 3)
        self.assertEqual(self.db.execute('SELECT status FROM knowledge_claims WHERE id=?', (old,)).fetchone()[0], 'historical')
        with self.assertRaisesRegex(ValueError, 'confirmation_not_supported'):
            evidence.propose_claim(self.db, dict(candidate, kind='confirmed_decision'))
        with self.assertRaisesRegex(ValueError, 'verification_not_supported'):
            evidence.propose_claim(self.db, dict(a, status='current'))
        with self.assertRaises(ValueError):
            evidence.propose_claim(self.db, dict(a, sourceHash=''))


if __name__ == '__main__':
    unittest.main()
