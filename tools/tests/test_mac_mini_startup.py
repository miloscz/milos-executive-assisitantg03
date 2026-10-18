import importlib.util
import os
from pathlib import Path
import plistlib
import tempfile
import unittest

module = importlib.util.spec_from_file_location('startup', Path(__file__).parents[1] / 'deployment/mac-mini-startup.py')
startup = importlib.util.module_from_spec(module)
module.loader.exec_module(startup)


class StartupSecurityTests(unittest.TestCase):
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
