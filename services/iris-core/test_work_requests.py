from copy import deepcopy
from datetime import datetime,timedelta
import json
import os
import threading
from pathlib import Path
import socket
import tempfile
import unittest
import uuid
from unittest.mock import patch

import briefing
import evidence
import knowledge_preparation
from private_store import Store
import recording_pilot
from test_private_evidence import native,legacy,AT,EVENT,BINDING
import workflow
import work_requests as work
import work_bridge


def random_id():return str(uuid.uuid4())


class WorkRequestsTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.runtime=Path(self.tmp.name)/'runtime'
        self.patches=[patch.object(briefing,'RUNTIME',self.runtime),patch.object(workflow,'RUNTIME',self.runtime),
          patch.object(workflow,'now_utc',return_value=datetime.fromisoformat(AT.replace('Z','+00:00')))]
        for p in self.patches:p.start()
        raw=native();self.packet={'date':'2026-10-19',**{k:raw[k] for k in ['active','calendar','sources']}}
        with patch.object(recording_pilot,'legacy_read',side_effect=legacy):
            self.packet['knowledge']=knowledge_preparation.sync(self.packet,EVENT,{'bindingRef':BINDING},AT)
        self.packet['hash']=workflow.packet_hash(self.packet)
        briefing.private_write('briefing-packet.json',self.packet)
        workflow.publish_views(self.packet,datetime(2026,10,19).date(),{'phase':'prepare','targetDate':'2026-10-19','state':'partial','updatedAt':AT},self.packet['knowledge']['cards'])
        self.item=raw['calendar']['records'][0]['id']
        self.detail=work.current(self.item)[1]

    def tearDown(self):
        for p in reversed(self.patches):p.stop()
        self.tmp.cleanup()

    def revision(self):
        return {'requestId':random_id(),'id':self.item,'preparationVersion':self.detail['version'],
                'topic':'options','instruction':'Compare a short pilot with a full mobile client.','directUserCommand':True}

    def decision(self):
        return {'requestId':random_id(),'id':self.item,'preparationVersion':self.detail['version'],
                'decision':'Choose an evaluation pilot; assign no budget or external action.'}

    def test_revision_is_durable_idempotent_and_requires_a_cited_deliverable(self):
        request=self.revision();first=work.handle('request_revision',request)
        self.assertEqual(first['workRequest']['state'],'queued')
        self.assertEqual(work.handle('request_revision',request),first)
        self.assertEqual(work.handle('request_revision',{**request,'instruction':'different'})['error'],'requestConflict')
        self.assertEqual(work.next_request()['state'],'needsAnalysis')
        inp=workflow.private_read('work-analysis-input.json',131072)
        card=deepcopy(self.packet['knowledge']['cards'][0]);card['context']='Revised synthetic analysis with explicit missing inputs.'
        draft={'requestId':request['requestId'],'preparationVersion':request['preparationVersion'],
               'packetHash':self.packet['hash'],'card':card,'sections':[{'kind':'options','text':'A bounded evaluation is proposed; implementation remains unapproved.'}],
               'summary':'Pilot comparison prepared; capacity still missing.'}
        bad=deepcopy(draft);bad['card']['evidence'][0]['quote']='This quote does not exist in the actual source.'
        briefing.private_write('work-analysis-output.json',bad)
        with self.assertRaises(ValueError):work.publish_request()
        briefing.private_write('work-analysis-output.json',draft)
        self.assertEqual(work.publish_request()['state'],'completed')
        result=work.handle('get_request',{'requestId':request['requestId']})['workRequest']
        self.assertEqual(result['state'],'completed');self.assertNotEqual(result['resultVersion'],request['preparationVersion'])
        self.assertEqual(work.current(self.item)[1]['version'],result['resultVersion'])
        self.assertEqual(work.current(self.item)[0]['sourceFetchedAt'],AT)
        # Rebuilding the same unchanged source publication replays the persisted result.
        workflow.publish_views(self.packet,datetime(2026,10,19).date(),{'phase':'prepare','targetDate':'2026-10-19','state':'partial','updatedAt':AT},self.packet['knowledge']['cards'])
        self.assertEqual(work.current(self.item)[1]['version'],result['resultVersion'])
        with Store(self.runtime).locked() as s:self.assertTrue(s.backup_check()['restoredRowsMatch'])

    def test_decision_requires_new_confirmation_and_is_not_external_authority(self):
        candidate=self.decision();draft=work.handle('prepare_decision',candidate)['workRequest']
        self.assertEqual(draft['state'],'awaitingConfirmation');self.assertEqual(work.recorded_decisions(),[])
        confirm={'requestId':random_id(),'decisionId':draft['requestId'],'confirmationId':draft['confirmationId'],'userConfirmed':True}
        self.assertFalse(work.handle('confirm_decision',{**confirm,'userConfirmed':False})['ok'])
        self.assertEqual(work.handle('confirm_decision',confirm)['workRequest']['state'],'recorded')
        self.assertEqual(work.handle('confirm_decision',confirm)['workRequest']['state'],'recorded')
        self.assertEqual(work.handle('get_request',{'requestId':confirm['requestId']})['workRequest']['state'],'recorded')
        self.assertEqual(len(work.recorded_decisions()),1)
        detail=work.current(self.item)[1]
        self.assertEqual(detail['decision']['text'],candidate['decision'])
        self.assertFalse(detail['decision']['externalExecutionAuthorized'])
        self.assertNotEqual(detail['version'],candidate['preparationVersion'])
        workflow.publish_views(self.packet,datetime(2026,10,19).date(),{'phase':'prepare','targetDate':'2026-10-19','state':'partial','updatedAt':AT},self.packet['knowledge']['cards'])
        self.assertEqual(work.current(self.item)[1]['version'],detail['version'])
        row=work.recorded_decisions()[0]
        self.assertEqual(row['confirmationEvidence'],'callerAttestedAfterReadback')
        self.assertFalse(row['externalExecutionAuthorized'])
        self.assertEqual(work.handle('get_request',{'requestId':draft['requestId']})['workRequest']['text'],candidate['decision'])

    def test_revision_after_decision_replays_in_order_and_marks_older_decision_basis(self):
        candidate=self.decision();draft=work.handle('prepare_decision',candidate)['workRequest']
        work.handle('confirm_decision',{'requestId':random_id(),'decisionId':draft['requestId'],'confirmationId':draft['confirmationId'],'userConfirmed':True})
        self.detail=work.current(self.item)[1]
        revision=self.revision();work.handle('request_revision',revision);work.next_request()
        card=deepcopy(self.packet['knowledge']['cards'][0])
        result={'requestId':revision['requestId'],'preparationVersion':revision['preparationVersion'],'packetHash':self.packet['hash'],
                'card':card,'sections':[{'kind':'options','text':'Revised options require checking the earlier choice.'}],'summary':'Comparison updated.'}
        briefing.private_write('work-analysis-output.json',result);work.publish_request()
        detail=work.current(self.item)[1]
        self.assertTrue(detail['decision']['basedOnOlderVersion'])
        workflow.publish_views(self.packet,datetime(2026,10,19).date(),{'phase':'prepare','targetDate':'2026-10-19','state':'partial','updatedAt':AT},self.packet['knowledge']['cards'])
        self.assertEqual(work.current(self.item)[1]['version'],detail['version'])

    def test_changed_version_or_expiry_cannot_confirm_or_silently_retarget(self):
        draft=work.handle('prepare_decision',self.decision())['workRequest']
        confirm={'requestId':random_id(),'decisionId':draft['requestId'],'confirmationId':draft['confirmationId'],'userConfirmed':True}
        with patch.object(workflow,'now_utc',return_value=datetime.fromisoformat(AT.replace('Z','+00:00'))+timedelta(minutes=11)):
            self.assertEqual(work.handle('confirm_decision',confirm)['error'],'confirmationExpired')
        draft=work.handle('prepare_decision',self.decision())['workRequest']
        confirm={'requestId':random_id(),'decisionId':draft['requestId'],'confirmationId':draft['confirmationId'],'userConfirmed':True}
        revision=self.revision();self.assertTrue(work.handle('request_revision',revision)['ok'])
        f=workflow.private_read('briefing-details.json',65536)
        f['details'][0]['title']='Changed synthetic preparation'
        f['details'][0]['version']=work.version(f['details'][0],f['date']);briefing.private_write('briefing-details.json',f)
        self.assertEqual(work.handle('confirm_decision',confirm)['error'],'versionChanged')
        self.assertEqual(work.next_request()['state'],'idle')
        self.assertEqual(work.handle('get_request',{'requestId':revision['requestId']})['workRequest']['state'],'superseded')
        self.assertEqual(work.recorded_decisions(),[])

    def test_stale_unknown_sensitive_and_outside_inputs_are_rejected(self):
        for method,value in [('execute',{}),('request_revision',{**self.revision(),'path':'/synthetic'}),
            ('request_revision',{**self.revision(),'instruction':'AC1=synthetic-secret'}),
            ('request_revision',{**self.revision(),'directUserCommand':False}),
            ('prepare_decision',{**self.decision(),'id':'unknown'})]:
            self.assertFalse(work.handle(method,value)['ok'])
        with patch.object(workflow,'now_utc',return_value=datetime.fromisoformat(AT.replace('Z','+00:00'))+timedelta(minutes=31)):
            self.assertEqual(work.handle('prepare_decision',self.decision())['error'],'stalePreparation')
            request=self.revision();self.assertTrue(work.handle('request_revision',request)['ok'])
            self.assertEqual(work.next_request()['state'],'awaitingSources')
            self.assertEqual(work.handle('get_request',{'requestId':request['requestId']})['workRequest']['state'],'awaitingSources')
        with Store(self.runtime).locked() as s:
            with s.db:s.db.execute("UPDATE store_meta SET value=? WHERE key='binding_ref'",('b'*64,))
        # Version remains about the published source; confirmation cannot cross the ledger binding.
        self.assertNotEqual(work.version(self.detail,'2026-10-20'),self.detail['version'])

    def test_stale_confirmation_queues_existing_work_but_cannot_be_replayed_after_refresh(self):
        clock=datetime.fromisoformat(AT.replace('Z','+00:00'))
        with workflow.locked_queue() as db:
            db.execute('INSERT INTO jobs VALUES (?,?,?,?,?,?,?)',('existing','prepare','2026-10-19','partial',AT,None,self.packet['hash']))
        with patch.object(workflow,'now_utc',return_value=clock+timedelta(minutes=29)):
            draft=work.handle('prepare_decision',self.decision())['workRequest']
        confirmation={'requestId':random_id(),'decisionId':draft['requestId'],'confirmationId':draft['confirmationId'],'userConfirmed':True}
        with patch.object(workflow,'now_utc',return_value=clock+timedelta(minutes=31)):
            self.assertEqual(work.handle('confirm_decision',confirmation)['error'],'stalePreparation')
        with workflow.locked_queue() as db:
            jobs=db.execute('SELECT * FROM jobs').fetchall()
            self.assertEqual(len(jobs),1);self.assertEqual(jobs[0]['id'],'existing');self.assertEqual(jobs[0]['state'],'queued')
        self.assertEqual(work.handle('get_request',{'requestId':draft['requestId']})['workRequest']['state'],'superseded')
        # Even if freshness is restored, the earlier rejected human command cannot be retried.
        self.assertEqual(work.handle('confirm_decision',confirmation)['error'],'confirmationRequired')
        self.assertEqual(work.recorded_decisions(),[])

    def test_private_socket_rejects_wrong_peer_and_oversized_input(self):
        for raw,peer in [(b'{"method":"exportToken","params":{}}\n',-1),(b'x'*8193,os.getuid())]:
            a,b=socket.socketpair()
            a.settimeout(2);b.settimeout(2)
            with patch.object(work_bridge,'peer_uid',return_value=peer):
                thread=threading.Thread(target=work_bridge.serve_connection,args=(a,));thread.start()
                try:b.sendall(raw)
                except BrokenPipeError:pass
                result=b.recv(16384);thread.join(3)
            b.close()
            self.assertEqual(json.loads(result)['ok'],False)
            self.assertNotIn(b'exportToken',result)


    def test_real_local_socket_authenticates_same_uid_and_handles_one_bounded_method(self):
        listener,lock,thread=work_bridge.start_bridge()
        try:
            client=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM);client.settimeout(3)
            client.connect(str(self.runtime/'w.sock'))
            client.sendall(json.dumps({'method':'get_request','params':{'requestId':random_id()}}).encode()+b'\n')
            result=json.loads(client.recv(16384));client.close()
            self.assertEqual(result,{'ok':False,'error':'notFound'})
        finally:
            listener.close();thread.join(2);os.close(lock)


if __name__=='__main__':unittest.main()
