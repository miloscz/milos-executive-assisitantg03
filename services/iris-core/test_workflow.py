from datetime import datetime,timezone,date
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import workflow
import briefing


class WorkflowTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.folder=Path(self.temp.name)/'runtime'
        self.patches=[patch.object(workflow,'RUNTIME',self.folder),patch.object(briefing,'RUNTIME',self.folder)]
        for p in self.patches:p.start()
    def tearDown(self):
        for p in self.patches:p.stop()
        self.temp.cleanup()
    def test_prague_workdays_friday_weekend_and_dst(self):
        for stamp,expected in [('2026-10-23T16:00:00+00:00','2026-10-26'),('2026-10-18T16:00:00+00:00','2026-10-19'),('2026-10-26T17:00:00+00:00','2026-10-27')]:
            self.assertEqual(workflow.target_day('prepare',datetime.fromisoformat(stamp)).isoformat(),expected)
        self.assertEqual(workflow.target_day('morning',datetime.fromisoformat('2026-10-18T22:05:00+00:00')),date(2026,10,19))
    def test_waiting_survives_restart_and_only_prepares_never_starts_mfa(self):
        with workflow.locked_queue() as db:
            db.execute('INSERT INTO jobs VALUES (?,?,?,?,?,?,?)',('synthetic','prepare','2026-10-19','queued','2026-10-18T16:00:00Z',None,None));db.commit()
            job=db.execute('SELECT * FROM jobs').fetchone()
            calls=[]
            def helper(kind,operation,*args):
                calls.append((kind,operation))
                if operation=='status':return {'ok':True,'enabled':True,'sessionValid':False,'busy':False,'state':{'eventID':'247149A1-25EB-4D9D-805F-1F1F79F01814'}}
                self.assertEqual((kind,operation),('IrisControl','prepare'));return {'ok':True}
            with patch.object(workflow,'helper',side_effect=helper):
                self.assertEqual(workflow.run_job(db,job)['state'],'awaitingAccess')
            self.assertEqual(calls,[('IrisControl','status'),('IrisControl','prepare')])
        with workflow.locked_queue() as db:self.assertEqual(db.execute('SELECT state FROM jobs').fetchone()['state'],'awaitingAccess')
        for operation in ['start','noticeSent','http','readFile']:
            with self.assertRaises(ValueError):workflow.helper('IrisControl',operation)
    def test_duplicate_job_and_concurrent_worker_cannot_duplicate_work(self):
        with workflow.locked_queue() as db:
            row=('synthetic','prepare','2026-10-19','queued','2026-10-18T16:00:00Z',None,None)
            for _ in range(2):db.execute('INSERT OR IGNORE INTO jobs VALUES (?,?,?,?,?,?,?)',row)
            self.assertEqual(db.execute('SELECT count(*) FROM jobs').fetchone()[0],1)
            with self.assertRaises(BlockingIOError):
                with workflow.locked_queue():pass
    def test_no_arbitrary_file_or_symlink_read(self):
        with self.assertRaises(ValueError):workflow.private_read('../secret',4096)
        workflow.directory();target=self.folder/'synthetic';target.write_text('{}')
        (self.folder/'briefing-analysis.json').symlink_to(target)
        with self.assertRaises(OSError):workflow.private_read('briefing-analysis.json',65536)
    def test_missing_native_pairing_is_waiting_not_a_permanent_job_failure(self):
        with patch.object(workflow,'helper',side_effect=ValueError('unavailable')):
            with self.assertRaisesRegex(ValueError,'pairingRequired'):workflow.access()
    def packet(self):
        url='https://uuapp.plus4u.net/uu-managementkit-maing02/'+'a'*32+'/document?oid='+'b'*24
        record={'id':'decision','name':'Synthetic decision','activityType':'decide','ownElementaryState':'initial','endTime':'2026-10-19T08:00:00Z','sourceURL':url,'description':'Synthetic request'}
        page={'pageId':'c'*24,'text':'The documented synthetic fact supports option A.','complete':True}
        p={'date':'2026-10-19','active':{'operation':'tasks.listActive','scope':'self','complete':True,'contractVerified':True,'fetchedAt':'2026-10-18T16:00:00Z','records':[record]},'calendar':None,
           'sources':{'complete':True,'materials':[{'recordId':'decision','sourceURL':url,'pages':[page],'complete':True,'preparationText':page['text'],'minutesText':'','fetchedAt':'2026-10-18T16:00:00Z'}]}}
        p['hash']=workflow.packet_hash(p)
        return p
    def draft(self,p):
        return {'date':p['date'],'packetHash':p['hash'],'cards':[{'id':'decision','kind':'decision','readiness':'prepared','context':'A synthetic fact is documented.','questions':[],'missing':[],'nextStep':'Review option A.',
        'evidence':[{'sourceURL':p['sources']['materials'][0]['sourceURL'],'pageId':'c'*24,'quote':'The documented synthetic fact supports option A.'}]}]}
    def test_analysis_is_bound_to_current_packet_and_real_quotes(self):
        p=self.packet();d=self.draft(p)
        self.assertEqual(len(workflow.validate_analysis(d,p)),1)
        d['cards'][0]['evidence'][0]['quote']='An invented synthetic assertion.'
        with self.assertRaises(ValueError):workflow.validate_analysis(d,p)
        d=self.draft(p);p['sources']['materials'][0]['pages'][0]['text']='Changed content'
        with self.assertRaises(ValueError):workflow.validate_analysis(d,p)
    def test_unchanged_content_can_reuse_analysis_but_missing_cards_are_not_ready(self):
        p=self.packet();before=p['hash'];p['active']['fetchedAt']='2026-10-19T05:00:00Z'
        self.assertEqual(workflow.packet_hash(p),before)
        self.assertEqual(workflow.prepared_state(p,[]),'partial')
        self.assertEqual(workflow.prepared_state(p,self.draft(p)['cards']),'ready')
    def test_grounded_correction_retains_packet_binding_and_rejects_stale_or_superseded_work(self):
        p=self.packet();d=self.draft(p)
        briefing.private_write('briefing-packet.json',p);briefing.private_write('briefing-analysis.json',d)
        with workflow.locked_queue() as db:
            db.execute('INSERT INTO jobs VALUES (?,?,?,?,?,?,?)',('synthetic','prepare',p['date'],'partial','2026-10-18T16:01:00Z',None,p['hash']));db.commit()
            with patch.object(workflow,'now_utc',return_value=datetime.fromisoformat('2026-10-18T16:05:00+00:00')):
                self.assertEqual(workflow.publish_analysis(db)['state'],'ready')
            with self.assertRaisesRegex(ValueError,'stale_sources'):
                with patch.object(workflow,'now_utc',return_value=datetime.fromisoformat('2026-10-18T17:00:00+00:00')):workflow.publish_analysis(db)
            db.execute("UPDATE jobs SET state='superseded'");db.commit()
            with self.assertRaisesRegex(ValueError,'no_analysis_job'):workflow.publish_analysis(db)


if __name__=='__main__':unittest.main()
