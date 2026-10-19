import json
import os
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

import analysis_engine as engine


class AnalysisEngineTests(unittest.TestCase):
    def value(self):return {'date':'2026-10-20','packetHash':'a'*64,'items':[]}

    def test_command_uses_fixed_isolation_no_inherited_config_and_disabled_tools(self):
        args=engine.command(Path('/fixed/codex'),Path('/private/tmp/synthetic'))
        self.assertEqual(args[0],'/usr/bin/sandbox-exec')
        for flag in ['--ignore-user-config','--ephemeral','--output-schema','read-only','mcp_servers={}']:
            self.assertIn(flag,args)
        self.assertIn('model_reasoning_effort="high"',args)
        self.assertEqual(args[args.index('--model')+1],'gpt-6.1-sol')
        for feature in ['shell_tool','apps','plugins','multi_agent','code_mode','code_mode_host']:
            self.assertIn(feature,args)
        profile=engine.PROFILE.read_text()
        self.assertIn('(deny process-exec)',profile)
        self.assertIn('(deny network-outbound (subpath (param "USER_HOME")))',profile)

    def fake(self,kind='agent_message',message=None,timeout=False):
        class Child:
            pid=99999999
            returncode=None
            def communicate(child,data,timeout=None):
                if timeout_mode:raise subprocess.TimeoutExpired('synthetic',timeout)
                folder=Path(call['cwd']);answer={'date':'2026-10-20','packetHash':'a'*64,'cards':[]}
                (folder/'answer.json').write_text(json.dumps(answer))
                event={'type':'item.completed','item':{'type':kind,**({'message':message} if message else {})}}
                call['stdout'].write(json.dumps(event).encode()+b'\n');child.returncode=0
            def poll(child):return child.returncode
            def wait(child):child.returncode=-9
        timeout_mode=timeout
        def popen(args,**kwargs):
            nonlocal call
            call=kwargs
            self.assertEqual(set(call['env']),{'HOME','PATH','TMPDIR'})
            self.assertTrue(call['start_new_session'])
            return Child()
        call={}
        return popen

    def test_bounded_final_json_and_known_disabled_host_notice(self):
        for kind,message in [('agent_message',None),('error',engine.DISABLED_HOST_NOTICE)]:
            with patch.object(engine,'checked_binary',return_value=Path('/fixed/codex')),patch.object(engine.subprocess,'Popen',side_effect=self.fake(kind,message)):
                self.assertEqual(engine.run(self.value())['cards'],[])

    def test_unknown_error_and_any_tool_attempt_fail_closed(self):
        for kind in ['error','command_execution','mcp_tool_call','web_search','collab_tool_call']:
            with patch.object(engine,'checked_binary',return_value=Path('/fixed/codex')),patch.object(engine.subprocess,'Popen',side_effect=self.fake(kind,'synthetic error')):
                with self.assertRaisesRegex(ValueError,'analysisRejected'):engine.run(self.value())

    def test_timeout_kills_only_its_own_process_group(self):
        with patch.object(engine,'checked_binary',return_value=Path('/fixed/codex')),patch.object(engine.subprocess,'Popen',side_effect=self.fake(timeout=True)),patch.object(engine.os,'killpg') as kill:
            with self.assertRaisesRegex(ValueError,'analysisTimeout'):engine.run(self.value(),1)
            kill.assert_called_once_with(99999999,engine.signal.SIGKILL)

    def test_sensitive_input_rejected_before_launch(self):
        value=self.value();value['text']='access_token: synthetic-value'
        with patch.object(engine.subprocess,'Popen') as launch:
            with self.assertRaises(ValueError):engine.run(value)
            launch.assert_not_called()

    def test_utf8_byte_budget_is_enforced_before_launch(self):
        value=self.value();value['text']='ž'*80000
        with patch.object(engine.subprocess,'Popen') as launch:
            with self.assertRaisesRegex(ValueError,'analysisRejected'):engine.run(value)
            launch.assert_not_called()

    def test_whitespace_normalization_changes_no_identifiers_or_content(self):
        d={'date':'synthetic','packetHash':'a'*64,'cards':[{'id':'same','context':'  one\n two  ',
            'nextStep':'<b>not removed</b>','questions':['a\tb'],'missing':[],
            'evidence':[{'sourceURL':'unchanged','pageId':'same','quote':'one\n two'}]}]}
        n=engine.normalize_whitespace(d)
        self.assertEqual(n['cards'][0]['context'],'one two')
        self.assertEqual(n['cards'][0]['evidence'][0],{'sourceURL':'unchanged','pageId':'same','quote':'one two'})
        self.assertEqual(n['cards'][0]['nextStep'],'<b>not removed</b>')


if __name__=='__main__':unittest.main()
