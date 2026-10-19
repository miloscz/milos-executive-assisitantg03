import os
from pathlib import Path
import sqlite3
import tempfile
import unittest
from unittest.mock import patch

import connect_evidence as adapter
import evidence
from private_store import Store
import recording_pilot

AT = '2026-10-18T20:50:00Z'
EVENT = '11111111-1111-4111-8111-111111111111'
BINDING = 'a' * 64
MEETING_URL = 'https://uuapp.plus4u.net/uu-elementarymanagement-maing01/76cc9f8077b44b43b90c3542bd257b55/meetingDetail?id=6accc261794626a48995763f'
TASK_URL = 'https://uuapp.plus4u.net/uu-managementkit-maing02/' + 'a' * 32 + '/meeting?oid=' + 'b' * 24


def native():
    meeting = dict(id=adapter.MEETING_RECORD, name='Synthetic recording meeting', description='Synthetic',
                   contentTruncated=False, kind='reservationOrInvitation', startTime='2026-10-19T09:00:00Z',
                   endTime='2026-10-19T09:30:00Z', showInDiary='timeBlock', activityState='active',
                   ownElementaryState='replanned', activityType='reserveTime', sourceURL=MEETING_URL,
                   rejected=False, cancelled=False)
    task = dict(meeting, id=adapter.TASK_RECORD, name='Synthetic transcription task', kind='unknown',
                activityType='doIt', ownElementaryState='initial', sourceURL=TASK_URL)
    def batch(op, records):
        return dict(operation=op, scope='self', complete=True, contractVerified=True, stale=False, bindingRef=BINDING,
                    fetchedAt=AT, records=records)
    calendar = batch('calendar.list', [meeting])
    calendar['dateWindow'] = dict(dateFrom=adapter.PILOT_DAY, dateTo=adapter.PILOT_DAY, timezone='Europe/Prague')
    material = dict(recordId=adapter.MEETING_RECORD, sourceURL=MEETING_URL, fetchedAt=AT, complete=False,
                    preparationText='Synthetic preparation for a mobile client.', minutesText='',
                    pages=[dict(pageId='synthetic-main', text='Synthetic preparation for a mobile client.', complete=False)])
    return dict(event=EVENT, bindingRef=BINDING, active=batch('tasks.listActive', [meeting, task]), calendar=calendar,
                sources=dict(ok=True, policy='iris-connect-briefing-sources-v1', fetchedAt=AT,
                             complete=False, bindingRef=BINDING, materials=[material]))


def legacy(relative):
    return dict(ref='legacy:' + relative, hash=evidence.digest(relative),
                text='Synthetic: 19. 10. 11:00–12:00 USY Sales stačí minutka STATUS: DRAFT awaiting Miloš')


class PrivateEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name) / 'runtime'

    def tearDown(self):
        self.tmp.cleanup()

    def test_private_modes_lock_and_backup_restore_rows(self):
        with Store(self.root).locked() as store:
            adapter.ingest(store, adapter.select_capture(native(), AT), AT)
            with self.assertRaises(BlockingIOError):
                with Store(self.root).locked():
                    pass
            result = store.backup_check()
            self.assertEqual(result, dict(integrity=True, restoredRowsMatch=True))
            store.write_json('pilot-report.json', {'synthetic': True})
            with self.assertRaises(ValueError):
                store.write_json('../escape.json', {})
        for folder in [self.root, self.root / 'work-evidence']:
            self.assertEqual(folder.stat().st_mode & 0o777, 0o700)
        for path in (self.root / 'work-evidence').iterdir():
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        with Store(self.root).locked() as store:
            self.assertEqual(store.metadata()['workItems'], 2)

    def test_symlink_hardlink_and_world_readable_fail_closed(self):
        with Store(self.root).locked():
            pass
        db = self.root / 'work-evidence/state.sqlite'
        db.chmod(0o644)
        with self.assertRaises(ValueError):
            with Store(self.root).locked():
                pass
        db.chmod(0o600)
        target = self.root / 'target.sqlite'
        db.rename(target)
        db.symlink_to(target)
        with self.assertRaises((ValueError, OSError)):
            with Store(self.root).locked():
                pass
        db.unlink()
        os.link(target, db)
        with self.assertRaises(ValueError):
            with Store(self.root).locked():
                pass

    def test_sidecar_and_runtime_symlinks_rejected(self):
        with Store(self.root).locked():
            pass
        sidecar = self.root / 'work-evidence/state.sqlite-journal'
        sidecar.symlink_to(self.root / 'outside')
        with self.assertRaises((ValueError, OSError)):
            with Store(self.root).locked():
                pass
        alias = Path(self.tmp.name) / 'alias'
        alias.symlink_to(self.root)
        with self.assertRaises(ValueError):
            with Store(alias).locked():
                pass

    def test_partial_stale_and_unknown_state_cannot_mutate_store(self):
        for modification in ['partial', 'stale', 'unknown', 'sensitive']:
            value = native()
            if modification == 'partial':
                value['active']['complete'] = False
            elif modification == 'stale':
                value['calendar']['fetchedAt'] = '2026-10-18T10:00:00Z'
            elif modification == 'unknown':
                value['active']['records'][1]['ownElementaryState'] = 'unrecognized'
            else:
                value['sources']['materials'][0]['preparationText'] = 'access_token: synthetic-must-not-persist'
            with self.subTest(modification=modification), Store(self.root).locked() as store:
                with self.assertRaises(ValueError):
                    adapter.ingest(store, adapter.select_capture(value, AT), AT)
                self.assertEqual(store.metadata()['workItems'], 0)

    def test_two_reads_deduplicate_knowledge_and_preserve_source_times(self):
        with patch.object(recording_pilot, 'legacy_read', side_effect=legacy):
            with Store(self.root).locked() as store:
                first = recording_pilot.run_capture(store, native(), AT)
            later = '2026-10-18T20:51:00Z'
            value = native()
            for key in ('active', 'calendar', 'sources'):
                value[key]['fetchedAt'] = later
            value['sources']['materials'][0]['fetchedAt'] = later
            with Store(self.root).locked() as store:
                second = recording_pilot.run_capture(store, value, later)
                self.assertEqual(store.metadata(), dict(schemaVersion=3, workItems=2, claims=7, captures=2))
                self.assertEqual(first['contentHash'], second['contentHash'])
                self.assertEqual(store.db.execute('SELECT count(*) FROM work_revisions').fetchone()[0], 2)
                self.assertEqual(store.db.execute('SELECT count(*) FROM personal_inbox').fetchone()[0], 1)
                self.assertEqual(store.db.execute('SELECT count(*) FROM preparation_steps').fetchone()[0], 2)
                self.assertEqual(store.db.execute("SELECT count(*) FROM knowledge_claims WHERE claim_kind='confirmed_decision'").fetchone()[0], 0)
                self.assertEqual(store.db.execute("SELECT route FROM intake_events WHERE route='review'").fetchone()[0], 'review')

    def test_changed_calendar_retains_id_and_new_login_reuses_same_binding(self):
        with Store(self.root).locked() as store:
            a = adapter.ingest(store, adapter.select_capture(native(), AT), AT)
            value = native()
            value['calendar']['records'][0]['endTime'] = '2026-10-19T10:00:00Z'
            b = adapter.ingest(store, adapter.select_capture(value, AT), AT)
            self.assertEqual(a['mapped'], b['mapped'])
            self.assertEqual(store.db.execute('SELECT count(*) FROM work_revisions').fetchone()[0], 3)
            value['event'] = '22222222-2222-4222-8222-222222222222'
            c = adapter.ingest(store, adapter.select_capture(value, AT), AT)
            self.assertEqual(c['mapped'], a['mapped'])
            self.assertEqual(store.metadata()['workItems'], 2)
            value['bindingRef'] = 'b' * 64
            for name in ('active','calendar','sources'):
                value[name]['bindingRef'] = value['bindingRef']
            with self.assertRaisesRegex(ValueError, 'scopeReviewRequired'):
                adapter.ingest(store, adapter.select_capture(value, AT), AT)
            self.assertEqual(store.metadata()['captures'], 3)

    def test_migration_from_offline_v1_and_rejection_of_newer_version(self):
        db = sqlite3.connect(':memory:')
        db.executescript(Path(evidence.__file__).with_name('evidence-schema.sql').read_text())
        evidence.migrate(db)
        self.assertEqual(db.execute('PRAGMA user_version').fetchone()[0], 3)
        db.execute('PRAGMA user_version=99')
        with self.assertRaisesRegex(ValueError, 'unsupported_database'):
            evidence.migrate(db)
        db.close()

    def test_database_capture_rollback_on_invalid_second_work_item(self):
        capture = adapter.select_capture(native(), AT)
        capture['records'][1]['ownElementaryState'] = 'unexpected'
        with Store(self.root).locked() as store:
            with self.assertRaises(ValueError):
                adapter.ingest(store, capture, AT)
            self.assertEqual(store.metadata()['workItems'], 0)
            self.assertEqual(store.db.execute('SELECT count(*) FROM work_revisions').fetchone()[0], 0)

    def test_legacy_review_failure_rolls_back_whole_capture(self):
        def changed(relative):
            return dict(legacy(relative), text='Synthetic edited note without reviewed anchors.')
        with patch.object(recording_pilot, 'legacy_read', side_effect=changed):
            with Store(self.root).locked() as store:
                with self.assertRaisesRegex(ValueError, 'legacy_content_review_required'):
                    recording_pilot.run_capture(store, native(), AT)
                self.assertEqual(store.metadata(), dict(schemaVersion=3, workItems=0, claims=0, captures=0))

    def test_native_path_only_calls_fixed_read_helpers_and_never_login(self):
        value = native()
        calls = []
        def helper(kind, operation, *args):
            self.assertEqual(kind, 'IrisRead')
            calls.append(operation)
            if operation == 'status':
                return dict(ok=True, policy='iris-connect-read-v1', paired=True, loginRequired=False, bindingRef=BINDING)
            if operation == 'diagnostics.calendarBoundaries':
                return {'verified': True}
            if operation == 'diagnostics.sources':
                return {'checks': []}
            return value[{'tasks.listActive': 'active', 'calendar.list': 'calendar', 'sources.prepare': 'sources'}[operation]]
        state = dict(enabled=True, sessionValid=True, busy=False, event=EVENT)
        with patch.object(adapter.workflow, 'access', return_value=state), patch.object(adapter.workflow, 'helper', side_effect=helper):
            adapter.fetch_native(calibrate=True)
        self.assertEqual(calls, ['status', 'diagnostics.calendarBoundaries', 'diagnostics.sources', 'tasks.listActive', 'calendar.list', 'sources.prepare', 'status'])
        with patch.object(adapter.workflow, 'access', return_value=dict(state, sessionValid=False)), patch.object(adapter.workflow, 'helper') as forbidden:
            with self.assertRaisesRegex(ValueError, 'loginRequired'):
                adapter.fetch_native(calibrate=True)
            forbidden.assert_not_called()

    def test_secret_like_document_content_and_unexpected_source_query_rejected(self):
        for text in ['{"access_token":"synthetic-value"}', 'AC1 = synthetic-value',
                     'Authorization: Bearer synthetic-value']:
            with self.subTest(text=text), self.assertRaisesRegex(ValueError, 'sensitive_source_content'):
                adapter.safe_text(text, 1000)
        with self.assertRaises(ValueError):
            adapter.source_ref(MEETING_URL + '&id=' + 'a' * 24)


if __name__ == '__main__':
    unittest.main()
