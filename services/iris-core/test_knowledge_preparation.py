from copy import deepcopy
from datetime import datetime
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import briefing
import connect_evidence as adapter
import evidence
import knowledge_preparation as knowledge
from private_store import Store
import recording_pilot
from test_private_evidence import native, legacy, AT, EVENT, BINDING
import workflow


class KnowledgePreparationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name) / 'runtime'
        self.patch = patch.object(briefing, 'RUNTIME', self.root)
        self.patch.start()
        self.workflow_patch=patch.object(workflow,'RUNTIME',self.root)
        self.workflow_patch.start()

    def tearDown(self):
        self.patch.stop()
        self.workflow_patch.stop()
        self.tmp.cleanup()

    def packet(self):
        value = native()
        return {'date':adapter.PILOT_DAY, 'active':value['active'], 'calendar':value['calendar'], 'sources':value['sources']}

    def test_daily_sync_prepares_cited_card_and_bounded_followup_without_duplicates(self):
        packet = self.packet()
        binding = dict(bindingRef=BINDING)
        with patch.object(recording_pilot,'legacy_read',side_effect=legacy):
            packet['knowledge'] = knowledge.sync(packet, EVENT, binding, AT)
            again = knowledge.sync(packet, '22222222-2222-4222-8222-222222222222', binding, AT)
        self.assertEqual(packet['knowledge']['cards'], again['cards'])
        packet['hash'] = workflow.packet_hash(packet)
        cards = workflow.merge_knowledge(packet, [])
        self.assertEqual(cards[0]['readiness'], 'prepared')
        self.assertTrue(cards[0]['missing'])
        self.assertIn('Varianty navržené Iris', cards[0]['context'])
        self.assertEqual(again['details'][0]['readiness'], 'partial')
        with Store(self.root).locked() as store:
            self.assertEqual(store.metadata()['workItems'], 2)
            self.assertEqual(store.metadata()['claims'], 7)
        changed=deepcopy(packet)
        changed['knowledge']['cards'][0]['nextStep']='A changed synthetic proposal'
        self.assertNotEqual(workflow.packet_hash(changed), packet['hash'])
        changed['hash']=workflow.packet_hash(changed)
        changed['sources']['materials'][0]['pages'][0]['text']='Different source'
        with self.assertRaises(ValueError):workflow.merge_knowledge(changed,[])

    def test_old_v2_scope_adoption_requires_both_native_prior_ref_and_preupgrade_epoch(self):
        value=native();capture=adapter.select_capture(value,AT)
        with Store(self.root).locked() as store:
            # Recreate the previous pilot's namespace/epoch, not a new account.
            oldscope='native-self-epoch:'+evidence.digest(EVENT)
            original=[]
            for record in capture['records']:
                normalized=adapter.normalize(record,BINDING);normalized['workspace']=oldscope
                original.append(evidence.upsert_work(store.db,normalized,AT))
            with store.db:store.db.execute("INSERT INTO store_meta VALUES ('native_epoch',?)",(EVENT,))
            with self.assertRaisesRegex(ValueError,'scopeReviewRequired'):adapter.ingest(store,capture,AT)
            with store.db:store.db.execute("INSERT INTO store_meta VALUES ('legacy_scope_verified',?)",(EVENT,))
            with self.assertRaisesRegex(ValueError,'scopeReviewRequired'):adapter.ingest(store,capture,AT)
            capture['previousBindingRef']=BINDING
            result=adapter.ingest(store,capture,AT)
            self.assertEqual(set(result['mapped'].values()),set(original))
            self.assertEqual(store.metadata()['workItems'],2)
            self.assertEqual(store.db.execute('SELECT count(*) FROM work_revisions').fetchone()[0],4)
            capture['event']='22222222-2222-4222-8222-222222222222'
            self.assertEqual(adapter.ingest(store,capture,AT)['mapped'],result['mapped'])

    def test_unrelated_day_does_not_attach_recording_knowledge(self):
        packet=self.packet();packet['calendar']['records']=[]
        self.assertEqual(knowledge.sync(packet,EVENT,dict(bindingRef=BINDING),AT)['state'],'notRelevant')

    def test_prepare_and_morning_jobs_publish_knowledge_and_followup_on_same_day(self):
        value=native()
        def helper(kind,operation,*args):
            if kind=='IrisControl':
                self.assertEqual(operation,'status')
                return dict(ok=True,enabled=True,sessionValid=True,busy=False,state={'eventID':EVENT})
            if operation=='status':return dict(ok=True,policy='iris-connect-read-v1',paired=True,loginRequired=False,bindingRef=BINDING)
            if operation=='diagnostics.calendarBoundaries':return {'verified':True}
            if operation=='diagnostics.sources':return {'checks':[]}
            return value[{'tasks.listActive':'active','calendar.list':'calendar','sources.prepare':'sources'}[operation]]
        with patch.object(workflow,'helper',side_effect=helper),patch.object(workflow,'now_utc',return_value=datetime.fromisoformat(AT.replace('Z','+00:00'))),patch.object(recording_pilot,'legacy_read',side_effect=legacy):
            for phase in ['prepare','morning']:
                with workflow.locked_queue() as db:
                    key=phase+'/'+adapter.PILOT_DAY
                    db.execute('INSERT INTO jobs VALUES (?,?,?,?,?,?,?)',(key,phase,adapter.PILOT_DAY,'queued',AT,None,None));db.commit()
                    row=db.execute('SELECT * FROM jobs WHERE id=?',(key,)).fetchone()
                    self.assertEqual(workflow.run_job(db,row)['state'],'needsAnalysis')
                brief=workflow.private_read('morning-briefing.json',24576)
                prepared=next(c for c in brief['preparations'] if c['id']==adapter.MEETING_RECORD)
                self.assertEqual(prepared['readiness'],'prepared')
                self.assertIn('Varianty navržené Iris',prepared['context'])
                details=workflow.private_read('briefing-details.json',65536)
                self.assertEqual(details['briefingGeneratedAt'],brief['generatedAt'])
                self.assertEqual(details['details'][0]['readiness'],'partial')
                source_input=workflow.private_read('analysis-input.json',131072)
                self.assertTrue(next(x for x in source_input['items'] if x['id']==adapter.MEETING_RECORD)['preparedContext'])
        with Store(self.root).locked() as store:self.assertEqual(store.metadata()['workItems'],2)
