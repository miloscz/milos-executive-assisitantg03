import importlib.util
import os
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch
from types import SimpleNamespace
import json

module = importlib.util.spec_from_file_location('startup', Path(__file__).parents[1] / 'deployment/mac-mini-startup.py')
startup = importlib.util.module_from_spec(module)
module.loader.exec_module(startup)
power_module=importlib.util.spec_from_file_location('awake',Path(__file__).parents[1]/'deployment/iris-awake.py')
awake=importlib.util.module_from_spec(power_module);power_module.loader.exec_module(awake)


class StartupSecurityTests(unittest.TestCase):
    def test_ac_guard_only_prevents_idle_sleep_and_releases_on_battery(self):
        from unittest.mock import Mock
        child=Mock();child.poll.return_value=None
        with patch.object(awake.subprocess,'Popen',return_value=child) as spawn:
            guard=awake.Guard();guard.refresh(True);guard.refresh(True)
            spawn.assert_called_once()
            self.assertEqual(spawn.call_args.args[0],['/usr/bin/caffeinate','-i','-w',str(os.getpid())])
            self.assertEqual(spawn.call_args.kwargs['env'],{'PATH':'/usr/bin:/bin'})
            guard.refresh(False);child.terminate.assert_called_once();self.assertIsNone(guard.child)
        spec=startup.awake_spec(Path('/synthetic/repo'))
        self.assertEqual(spec['Label'],startup.AWAKE)
        self.assertEqual(spec['ProgramArguments'],['/usr/bin/python3','-E','-s','/synthetic/repo/tools/deployment/iris-awake.py'])
        self.assertNotIn('EnvironmentVariables',spec)

    def test_ac_detection_fails_closed_on_battery_or_unknown_output(self):
        for value,expected in [(b"Now drawing from 'AC Power'\n",True),(b"Now drawing from 'Battery Power'\n",False),(b'',False),(b'unknown',False)]:
            with patch.object(awake.subprocess,'run',return_value=SimpleNamespace(returncode=0,stdout=value)):
                self.assertEqual(awake.on_ac(),expected)

    def test_worker_can_only_resume_fixed_local_workflow_without_shell_or_secrets(self):
        spec=startup.worker_spec(Path('/synthetic/repo'))
        self.assertEqual(spec['ProgramArguments'],['/usr/bin/python3','-E','-s','/synthetic/repo/services/iris-core/workflow.py','watch'])
        self.assertNotIn('EnvironmentVariables',spec)
        self.assertNotIn('StartCalendarInterval',spec)
        self.assertEqual(spec['Umask'],0o077)
        self.assertEqual(spec['StandardOutPath'],'/dev/null')

    def test_mcp_restart_tracks_only_its_own_children(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);label='net.iris.mcp-host.login'
            (root/(label+'.plist')).write_bytes(plistlib.dumps(startup.spec(root,label)))
            before={100:(1,'IrisMCPHost'),101:(100,'tunnel-client'),102:(101,'node'),999:(1,'IrisConnect')}
            after={999:(1,'IrisConnect')};calls=[]
            with patch.object(startup,'status',return_value={'jobs':{label:{'pid':100}}}),patch.object(startup,'process_table',side_effect=[before,after]),patch.object(startup,'run',side_effect=lambda args:(calls.append(args) or SimpleNamespace(returncode=0,stdout=b''))):
                startup.mcp_job('stop-mcp',root,root)
            self.assertEqual(len(calls),1)
            self.assertEqual(calls[0][:2],['/bin/launchctl','bootout'])
            self.assertTrue(calls[0][-1].endswith('/'+label))

    def test_connect_update_refuses_active_login_and_never_stops_tunnel(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            label = 'net.iris.connect.login'
            (root / (label + '.plist')).write_bytes(plistlib.dumps(startup.spec(root, label)))
            def reply(args):
                if args[-1] == 'status':
                    return SimpleNamespace(returncode=0,stdout=json.dumps({'ok':True,'busy':True}).encode())
                self.fail('active login must not reach a process or job mutation')
            with patch.object(startup,'run',side_effect=reply):
                with self.assertRaisesRegex(ValueError,'active_login'):
                    startup.connect_job('stop-connect',root,root)
            calls=[]
            def stopped(args):
                calls.append(args)
                if args[-1]=='status':return SimpleNamespace(returncode=0,stdout=b'{"ok":true,"busy":false}')
                return SimpleNamespace(returncode=1 if args[0]=='/usr/bin/pgrep' else 0,stdout=b'')
            with patch.object(startup,'run',side_effect=stopped):startup.connect_job('stop-connect',root,root)
            self.assertTrue(any('bootout' in x for x in calls))
            self.assertFalse(any('mcp-host' in str(x) for x in calls))

    def test_explicit_target_does_not_allow_other_accounts_or_checkout_paths(self):
        for target, account in [('mac-mini', 'irisagent'), ('current-mac', 'milosvodrazka')]:
            home = Path('/Users') / account
            repo = home / 'Personal/milos-executive-assisitantg03'
            self.assertTrue(startup.allowed_target(target, 'darwin', account, home, repo))
            self.assertFalse(startup.allowed_target(target, 'linux', account, home, repo))
            self.assertFalse(startup.allowed_target(target, 'darwin', 'other', home, repo))
            self.assertFalse(startup.allowed_target(target, 'darwin', account, Path('/tmp'), repo))
            self.assertFalse(startup.allowed_target(target, 'darwin', account, home, home / 'foreign'))
            other_target = 'current-mac' if target == 'mac-mini' else 'mac-mini'
            self.assertFalse(startup.allowed_target(other_target, 'darwin', account, home, repo))
        self.assertFalse(startup.allowed_target('unknown', 'darwin', 'other', Path('/Users/other'), Path('/Users/other/Personal/milos-executive-assisitantg03')))

    def test_only_fixed_gui_apps_without_secret_environment_or_shell(self):
        for label in startup.JOBS:
            spec = startup.spec(Path('/synthetic/repo with spaces'), label)
            self.assertEqual(len(spec['ProgramArguments']), 1)
            self.assertNotIn('EnvironmentVariables', spec)
            self.assertEqual(spec['LimitLoadToSessionType'], 'Aqua')
            self.assertEqual(spec['StandardOutPath'], '/dev/null')
            self.assertEqual(spec['StandardErrorPath'], '/dev/null')
            self.assertEqual(spec['KeepAlive'], {'SuccessfulExit': False})
        with self.assertRaises(KeyError):
            startup.spec(Path('/synthetic'), 'foreign.label')

    def test_refuses_foreign_job_and_symlink_before_overwriting(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'job.plist'
            expected = startup.spec(Path('/synthetic'), 'net.iris.connect.login')
            path.write_bytes(plistlib.dumps(expected))
            startup.checked_existing(path, expected)
            original = path.read_bytes()
            with self.assertRaises(ValueError):
                startup.checked_existing(path, {**expected, 'RunAtLoad': False})
            self.assertEqual(path.read_bytes(), original)
            link = Path(folder) / 'link.plist'
            link.symlink_to(path)
            with self.assertRaises(ValueError):
                startup.checked_existing(link, expected)


if __name__ == '__main__':
    unittest.main()
