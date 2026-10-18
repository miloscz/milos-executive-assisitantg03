import importlib.util
from pathlib import Path
from datetime import datetime, date, timezone
import unittest

spec=importlib.util.spec_from_file_location('briefing',Path(__file__).with_name('briefing.py'))
briefing=importlib.util.module_from_spec(spec);spec.loader.exec_module(briefing)

class BriefingTests(unittest.TestCase):
    def test_day_selection_conflicts_classification_and_no_completion_inference(self):
        def record(id,a,b,kind='reserveTime',state='initial',**extra):
            return dict(id=id,name='Synthetic '+id,startTime=a,endTime=b,activityType=kind,showInDiary='timeBlock',ownElementaryState=state,**extra)
        data=dict(operation='tasks.listActive',scope='self',complete=True,contractVerified=True,fetchedAt='2026-10-18T16:00:00Z',records=[
            record('overlap1','2026-10-19T08:00:00Z','2026-10-19T09:00:00Z'),
            record('overlap2','2026-10-19T08:30:00Z','2026-10-19T10:00:00Z'),
            record('endsAtStart','2026-10-18T20:00:00Z','2026-10-18T22:00:00Z'),
            record('startsAtEnd','2026-10-19T22:00:00Z','2026-10-19T23:00:00Z'),
            record('cancelled','2026-10-19T08:00:00Z','2026-10-19T10:00:00Z',cancelled=True),
            record('pending','2026-10-18T10:00:00Z','2026-10-18T10:00:00Z','decide'),
            record('solved','2026-10-18T10:00:00Z','2026-10-18T10:00:00Z','doIt','solvedActive'),
            record('unknown','2026-10-18T10:00:00Z','2026-10-18T10:00:00Z','doIt',None),
        ])
        value=briefing.compile_briefing(data,None,date(2026,10,19),datetime(2026,10,18,16,1,tzinfo=timezone.utc))
        self.assertEqual([r['id'] for r in value['schedule']],['overlap1','overlap2'])
        self.assertEqual(len(value['conflicts']),1)
        self.assertEqual([r['id'] for r in value['priorities']],['pending'])
        self.assertEqual(value['calendarCoverage'],'activeRecordsOnly')
        self.assertTrue(any('volný čas nelze' in x for x in value['warnings']))
        data['complete']=False
        with self.assertRaises(ValueError):briefing.compile_briefing(data,None,date(2026,10,19),datetime.now(timezone.utc))

    def test_offset_required_and_secret_and_link_minimization(self):
        with self.assertRaises(ValueError):briefing.instant('2026-10-19T12:00:00')
        self.assertNotIn('sk-',briefing.plain('sk-SYNTHETIC_SECRET_123456789'))
        self.assertEqual(briefing.source({'sourceURL':'https://uuapp.plus4u.net/x?token=synthetic'}),{})
        self.assertEqual(briefing.source({'sourceURL':'https://attacker.invalid/x'}),{})

if __name__=='__main__':unittest.main()
