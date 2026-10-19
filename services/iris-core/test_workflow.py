from datetime import datetime,timezone,date
import json
from pathlib import Path
import tempfile
import unittest
import io
from contextlib import redirect_stdout
from unittest.mock import patch

import workflow
import briefing


class WorkflowTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.folder=Path(self.temp.name)/'runtime'
        self.patches=[patch.object(workflow,'RUNTIME',self.folder),patch.object(briefing,'RUNTIME',self.folder),patch.object(workflow,'content_runtime_approved',return_value=True)]
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
    def test_queued_refresh_without_access_prepares_notice_but_never_starts_mfa(self):
        with workflow.locked_queue() as db:
            db.execute('INSERT INTO jobs VALUES (?,?,?,?,?,?,?)',('existing','prepare','2026-10-19','queued','2026-10-18T16:00:00Z',None,None))
            calls=[]
            def helper(kind,operation,*args):
                calls.append((kind,operation))
                if operation=='status':return {'ok':True,'enabled':True,'sessionValid':False,'busy':False,'state':{'eventID':'247149A1-25EB-4D9D-805F-1F1F79F01814'}}
                self.assertEqual((kind,operation),('IrisControl','prepare'));return {'ok':True}
            with patch.object(workflow,'helper',side_effect=helper):
                row=db.execute('SELECT * FROM jobs').fetchone()
                self.assertEqual(workflow.resume_existing(db,row)['state'],'awaitingAccess')
            self.assertEqual(calls,[('IrisControl','status'),('IrisControl','prepare')])

    def test_duplicate_job_and_concurrent_worker_cannot_duplicate_work(self):
        with workflow.locked_queue() as db:
            row=('synthetic','prepare','2026-10-19','queued','2026-10-18T16:00:00Z',None,None)
            for _ in range(2):db.execute('INSERT OR IGNORE INTO jobs VALUES (?,?,?,?,?,?,?)',row)
            self.assertEqual(db.execute('SELECT count(*) FROM jobs').fetchone()[0],1)
            with self.assertRaises(BlockingIOError):
                with workflow.locked_queue():pass
    def test_status_exposes_stale_completed_publication_without_reading_or_requeueing(self):
        now=datetime.fromisoformat('2026-10-19T05:20:00+00:00')
        old={'date':'2026-10-19','generatedAt':'2026-10-18T21:29:36Z','sourceFetchedAt':'2026-10-18T21:09:07Z',
             'workflow':{'phase':'morning'}}
        briefing.private_write('morning-briefing.json',old)
        with workflow.locked_queue() as db:
            db.execute('INSERT INTO jobs VALUES (?,?,?,?,?,?,?)',('morning/2026-10-19','morning','2026-10-19','partial','2026-10-18T21:29:36Z',None,None))
            with patch.object(workflow,'now_utc',return_value=now),patch.object(workflow,'helper',side_effect=AssertionError('status must not call native helper')):
                result=workflow.queue_status(db,None)
            self.assertEqual(result['state'],'partial');self.assertTrue(result['needsRefresh'])
            self.assertEqual(result['publication']['sourceFetchedAt'],old['sourceFetchedAt'])
            self.assertEqual(result['publication']['freshness'],'stale')
            self.assertEqual(db.execute('SELECT state FROM jobs').fetchone()[0],'partial')
            self.assertEqual(workflow.private_read('morning-briefing.json',24576),old)
            db.execute("UPDATE jobs SET state='awaitingAccess',error='loginRequired'")
            with patch.object(workflow,'now_utc',return_value=now):
                waiting=workflow.queue_status(db,db.execute('SELECT * FROM jobs').fetchone())
            self.assertEqual(waiting['state'],'awaitingAccess');self.assertEqual(waiting['error'],'loginRequired')
            self.assertFalse(waiting['needsRefresh'])
    def test_worker_classifies_lost_pairing_instead_of_leaving_awaiting_access(self):
        briefing.private_write('morning-briefing.json',{'sourceFetchedAt':'2026-10-18T21:09:07Z'})
        with workflow.locked_queue() as db:
            db.execute('INSERT INTO jobs VALUES (?,?,?,?,?,?,?)',('morning/2026-10-19','morning','2026-10-19','awaitingAccess','2026-10-19T04:40:00Z','loginRequired',None))
            row=db.execute('SELECT * FROM jobs').fetchone()
            with patch.object(workflow,'helper',side_effect=ValueError('unavailable')):
                result=workflow.resume_existing(db,row)
            self.assertEqual(result['state'],'awaitingBinding');self.assertEqual(result['error'],'pairingRequired')
            self.assertEqual(db.execute('SELECT state FROM jobs').fetchone()[0],'awaitingBinding')
            self.assertEqual(workflow.private_read('morning-briefing.json',24576)['sourceFetchedAt'],'2026-10-18T21:09:07Z')
    def test_waiting_episode_is_stable_until_access_actually_recovers(self):
        old={'date':'2026-10-19','generatedAt':'2026-10-18T21:29:36Z','sourceFetchedAt':'2026-10-18T21:09:07Z'}
        briefing.private_write('morning-briefing.json',old)
        with workflow.locked_queue() as db:
            db.execute('INSERT INTO jobs VALUES (?,?,?,?,?,?,?)',('morning/2026-10-19','morning','2026-10-19','queued','2026-10-19T04:40:00Z',None,None))
            def waiting_at(stamp):
                with patch.object(workflow,'now_utc',return_value=datetime.fromisoformat(stamp)):
                    workflow.waiting(db,db.execute('SELECT * FROM jobs').fetchone(),'awaitingAccess','loginRequired')
                return workflow.private_read('morning-briefing.json',24576)
            first=waiting_at('2026-10-19T04:45:00+00:00')
            repeated=waiting_at('2026-10-19T05:15:00+00:00')
            self.assertEqual(first['workflow']['updatedAt'],repeated['workflow']['updatedAt'])
            self.assertEqual(db.execute('SELECT updated FROM jobs').fetchone()[0],first['workflow']['updatedAt'])
            self.assertEqual(repeated['sourceFetchedAt'],old['sourceFetchedAt'])
            self.assertEqual(repeated['generatedAt'],old['generatedAt'])
            with patch.object(workflow,'now_utc',return_value=datetime.fromisoformat('2026-10-19T05:16:00+00:00')):
                workflow.waiting(db,db.execute('SELECT * FROM jobs').fetchone(),'queued',None)
            fresh_episode=waiting_at('2026-10-19T05:46:00+00:00')
            self.assertNotEqual(fresh_episode['workflow']['updatedAt'],first['workflow']['updatedAt'])
    def test_worker_resumes_same_waiting_job_after_login_without_another_mfa(self):
        from test_private_evidence import native,BINDING,EVENT
        raw=native();calls=[]
        old={'date':'2026-10-19','generatedAt':'2026-10-18T21:29:36Z','sourceFetchedAt':'2026-10-18T21:09:07Z',
             'workflow':{'phase':'morning','targetDate':'2026-10-19','state':'awaitingAccess','updatedAt':'2026-10-19T04:40:00Z'}}
        briefing.private_write('morning-briefing.json',old)
        for part in ('active','calendar','sources'):raw[part]['fetchedAt']='2026-10-19T04:50:00Z'
        def helper(kind,operation,*args):
            calls.append((kind,operation))
            if kind=='IrisControl':
                self.assertEqual(operation,'status')
                return {'enabled':True,'sessionValid':True,'busy':False,'state':{'eventID':EVENT}}
            if operation=='status':
                checkpoint=workflow.private_read('morning-briefing.json',24576)
                self.assertEqual(checkpoint['workflow']['state'],'queued')
                self.assertEqual(checkpoint['sourceFetchedAt'],old['sourceFetchedAt'])
                self.assertEqual(checkpoint['generatedAt'],old['generatedAt'])
                return {'ok':True,'policy':'iris-connect-read-v1','paired':True,'loginRequired':False,'bindingRef':BINDING}
            if operation=='diagnostics.calendarBoundaries':return {'verified':True}
            if operation=='diagnostics.sources':return {'checks':[]}
            return raw[{'tasks.listActive':'active','calendar.list':'calendar','sources.prepare':'sources'}[operation]]
        with workflow.locked_queue() as db:
            db.execute('INSERT INTO jobs VALUES (?,?,?,?,?,?,?)',('morning/2026-10-19','morning','2026-10-19','awaitingAccess','2026-10-19T04:40:00Z','loginRequired',None))
            row=db.execute('SELECT * FROM jobs').fetchone()
            with patch.object(workflow,'helper',side_effect=helper),patch.object(workflow,'now_utc',return_value=datetime.fromisoformat('2026-10-19T04:51:00+00:00')),patch('knowledge_preparation.sync',return_value={'state':'ready','cards':[],'details':[]}),patch('work_requests.recorded_decisions',return_value=[]),patch.object(workflow,'publish_views'):
                result=workflow.resume_existing(db,row)
            self.assertEqual(result['state'],'needsAnalysis')
            saved=db.execute('SELECT * FROM jobs').fetchall()
            self.assertEqual(len(saved),1);self.assertEqual(saved[0]['id'],row['id']);self.assertIsNone(saved[0]['error'])
            self.assertEqual(workflow.private_read('briefing-packet.json',8000000)['active']['fetchedAt'],'2026-10-19T04:50:00Z')
            self.assertEqual([call for call in calls if call[0]=='IrisControl'],[('IrisControl','status')])
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
    def test_explicit_refresh_reuses_published_job_without_creating_work_or_starting_mfa(self):
        with workflow.locked_queue() as db:
            db.execute('INSERT INTO jobs VALUES (?,?,?,?,?,?,?)',('prepare/2026-10-19','prepare','2026-10-19','partial','2026-10-18T16:00:00Z',None,None));db.commit()
        calls=[]
        def helper(kind,operation,*args):
            calls.append((kind,operation))
            if operation=='status':return {'enabled':True,'sessionValid':False,'busy':False,'state':{'eventID':'247149A1-25EB-4D9D-805F-1F1F79F01814'}}
            self.assertEqual(operation,'prepare');return {'ok':True}
        with patch.object(workflow.sys,'argv',['workflow.py','refresh']),patch.object(workflow,'now_utc',return_value=datetime.fromisoformat('2026-10-18T16:05:00+00:00')),patch.object(workflow,'helper',side_effect=helper),redirect_stdout(io.StringIO()):workflow.main()
        self.assertEqual(calls,[('IrisControl','status'),('IrisControl','prepare')])
        with workflow.locked_queue() as db:
            rows=db.execute('SELECT * FROM jobs').fetchall()
            self.assertEqual(len(rows),1);self.assertEqual(rows[0]['id'],'prepare/2026-10-19');self.assertEqual(rows[0]['state'],'awaitingAccess')

    def test_batch_registration_supersedes_older_unfinished_work_only(self):
        with workflow.locked_queue() as db:
            workflow.register_batch(db,'morning','2026-10-19')
            db.execute("INSERT INTO jobs VALUES ('history','prepare','2026-10-18','partial','2026-10-18T16:00:00Z',NULL,NULL)")
            a=workflow.register_batch(db,'prepare','2026-10-20')
            b=workflow.register_batch(db,'prepare','2026-10-20')
            self.assertEqual(a['id'],b['id'])
            self.assertEqual(db.execute("SELECT state FROM jobs WHERE id='morning/2026-10-19'").fetchone()[0],'superseded')
            self.assertEqual(db.execute("SELECT state FROM jobs WHERE id='history'").fetchone()[0],'partial')
            workflow.register_batch(db,'morning','2026-10-20')
            self.assertEqual(db.execute("SELECT state FROM jobs WHERE id=?",(a['id'],)).fetchone()[0],'superseded')

    def automatic_fixture(self,db):
        p=self.packet();p['active']['fetchedAt']=workflow.briefing.wire(workflow.now_utc())
        p['hash']=workflow.packet_hash(p)
        row=workflow.register_batch(db,'morning',p['date'])
        workflow.save(db,row,'needsAnalysis',packet_hash=p['hash'])
        briefing.private_write('briefing-packet.json',p)
        return db.execute('SELECT * FROM jobs WHERE id=?',(row['id'],)).fetchone(),p

    def test_automatic_analysis_publishes_once_and_idle_tick_never_calls_model(self):
        with workflow.locked_queue() as db:
            row,p=self.automatic_fixture(db)
            with patch('analysis_engine.run',return_value=self.draft(p)) as model,patch.object(workflow,'publish_views') as publication:
                result=workflow.complete_batch(db,row)
                self.assertEqual(result['state'],'ready');self.assertEqual(model.call_count,1)
                workflow.complete_batch(db,row)
                workflow.worker_tick(db)
                self.assertEqual(model.call_count,1);self.assertEqual(publication.call_count,1)
            self.assertEqual(workflow.private_read('briefing-packet.json',8000000)['active']['fetchedAt'],p['active']['fetchedAt'])
            self.assertEqual(db.execute('SELECT state,attempts FROM analysis_attempts').fetchone()[:],('completed',1))

    def test_automatic_failure_is_visible_and_never_retries_or_requests_mfa(self):
        with workflow.locked_queue() as db:
            row,p=self.automatic_fixture(db)
            with patch('analysis_engine.run',side_effect=ValueError('analysisTimeout')) as model,patch.object(workflow,'helper',side_effect=AssertionError('No MFA')):
                self.assertEqual(workflow.complete_batch(db,row)['error'],'analysisTimeout')
                workflow.complete_batch(db,row);workflow.worker_tick(db)
                self.assertEqual(model.call_count,1)
            self.assertEqual(db.execute('SELECT state FROM jobs').fetchone()[0],'failed')

    def test_interrupted_analysis_can_recover_only_once_and_ungrounded_output_is_rejected(self):
        with workflow.locked_queue() as db:
            row,p=self.automatic_fixture(db)
            db.execute('INSERT INTO analysis_attempts VALUES (?,?,?,?)',(row['id'],p['hash'],'running',1));db.commit()
            draft=self.draft(p);draft['cards'][0]['evidence'][0]['quote']='This is an invented citation.'
            with patch('analysis_engine.run',return_value=draft) as model,patch.object(workflow,'publish_views') as publication:
                result=workflow.complete_batch(db,row)
                self.assertEqual(result['error'],'analysisRejected');self.assertEqual(model.call_count,1);publication.assert_not_called()
            self.assertEqual(db.execute('SELECT attempts FROM analysis_attempts').fetchone()[0],2)

    def test_waiting_batch_completes_in_same_worker_tick_after_human_login(self):
        with workflow.locked_queue() as db:
            row,p=self.automatic_fixture(db);workflow.save(db,row,'awaitingAccess','loginRequired')
            p['active']['fetchedAt']='2026-10-19T04:59:00Z';briefing.private_write('briefing-packet.json',p)
            def recovered(db,job):
                self.assertEqual(job['id'],row['id'])
                workflow.save(db,job,'needsAnalysis',packet_hash=p['hash'])
            with patch.object(workflow,'now_utc',return_value=datetime.fromisoformat('2026-10-19T05:00:00+00:00')),patch.object(workflow,'resume_existing',side_effect=recovered),patch('analysis_engine.run',return_value=self.draft(p)),patch.object(workflow,'publish_views') as publication:
                self.assertEqual(workflow.worker_tick(db)['state'],'ready');publication.assert_called_once()
            self.assertEqual(db.execute('SELECT count(*) FROM jobs').fetchone()[0],1)

    def test_automatic_analysis_refuses_old_sources_without_retimestamping(self):
        with workflow.locked_queue() as db:
            row,p=self.automatic_fixture(db)
            with patch.object(workflow,'now_utc',return_value=workflow.briefing.instant(p['active']['fetchedAt'])+workflow.timedelta(minutes=31)),patch('analysis_engine.run') as model:
                self.assertEqual(workflow.complete_batch(db,row)['error'],'analysisRejected');model.assert_not_called()
            self.assertEqual(workflow.private_read('briefing-packet.json',8000000),p)

    def test_business_content_requires_exact_explicit_destination_approval(self):
        with workflow.locked_queue() as db:
            row,p=self.automatic_fixture(db)
            with patch.object(workflow,'content_runtime_approved',return_value=False),patch('analysis_engine.run') as model:
                self.assertEqual(workflow.complete_batch(db,row)['error'],'analysisApprovalRequired')
                model.assert_not_called()
            self.assertEqual(db.execute('SELECT count(*) FROM analysis_attempts').fetchone()[0],0)

    def test_content_approval_fails_closed_on_missing_changed_or_unapproved_contract(self):
        self.patches[2].stop()
        folder=Path(self.temp.name)/'policies';folder.mkdir()
        draft=folder/(workflow.CONTENT_POLICY+'.draft.json')
        contract={'policy':workflow.CONTENT_POLICY,'model':'gpt-6.1-sol','reasoning':'high'}
        draft.write_text(json.dumps(contract))
        approval=folder/(workflow.CONTENT_POLICY+'.approval.json')
        with patch.object(workflow,'ROOT',Path(self.temp.name)):
            self.assertFalse(workflow.content_runtime_approved())
            value={'policy':workflow.CONTENT_POLICY,'approved':True,'sha256':workflow.hashlib.sha256(draft.read_bytes()).hexdigest(),'basis':'humanDirect'}
            approval.write_text(json.dumps(value));self.assertTrue(workflow.content_runtime_approved())
            value['approved']='true';approval.write_text(json.dumps(value));self.assertFalse(workflow.content_runtime_approved())
            value['approved']=True;approval.write_text(json.dumps(value));draft.write_text('{"synthetic":"changed"}')
            self.assertFalse(workflow.content_runtime_approved())

    def test_approved_contract_cannot_select_another_model_or_reasoning(self):
        self.patches[2].stop()
        folder=Path(self.temp.name)/'policies';folder.mkdir()
        for model,reasoning in [('gpt-6.1-sol','low'),('gpt-5.6-sol','high')]:
            draft=folder/(workflow.CONTENT_POLICY+'.draft.json')
            draft.write_text(json.dumps({'policy':workflow.CONTENT_POLICY,'model':model,'reasoning':reasoning}))
            approval={'policy':workflow.CONTENT_POLICY,'approved':True,'sha256':workflow.hashlib.sha256(draft.read_bytes()).hexdigest(),'basis':'humanDirect'}
            (folder/(workflow.CONTENT_POLICY+'.approval.json')).write_text(json.dumps(approval))
            with patch.object(workflow,'ROOT',Path(self.temp.name)):
                self.assertFalse(workflow.content_runtime_approved())


if __name__=='__main__':unittest.main()
