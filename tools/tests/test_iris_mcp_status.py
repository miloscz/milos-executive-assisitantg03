import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from datetime import datetime, timezone

spec = importlib.util.spec_from_file_location('iris_mcp_status', Path(__file__).parents[1] / 'iris-mcp-status.py')
status = importlib.util.module_from_spec(spec)
spec.loader.exec_module(status)


class StatusTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.home = Path(self.temporary.name)
        self.folder = self.home / 'Library/Application Support/Iris MCP'
        self.folder.mkdir(parents=True)
        self.home_patch = patch.object(status.Path, 'home', return_value=self.home)
        self.home_patch.start()
        self.addCleanup(self.home_patch.stop)

    def receipt(self, **changes):
        data = dict(schemaVersion=2, stage='failed', running=False, ready=False,
                    failure='keychainDenied', timestamp=datetime.now(timezone.utc).isoformat())
        data.update(changes)
        (self.folder / 'verification.json').write_text(json.dumps(data))
        return status.read_status()

    def test_legacy_native_receipt_remains_readable(self):
        data = dict(schemaVersion=1, stage='failed', running=False, ready=False,
                    timestamp=datetime.now(timezone.utc).isoformat())
        (self.folder / 'verification.json').write_text(json.dumps(data))
        self.assertEqual(status.read_status()['stage'], 'failed')

    def test_fixed_failure_is_exposed_without_reflecting_unknown_payload(self):
        self.assertEqual(self.receipt()['failure'], 'keychainDenied')
        for changes in [dict(failure='SYNTHETIC_PRIVATE_CANARY'), dict(token='SYNTHETIC_PRIVATE_CANARY'), dict(failure={'token':'SYNTHETIC_PRIVATE_CANARY'})]:
            result = self.receipt(**changes)
            self.assertEqual(result['stage'], 'invalid_receipt')
            self.assertNotIn('SYNTHETIC_PRIVATE_CANARY', json.dumps(result))

    def test_failure_state_must_be_consistent(self):
        self.assertEqual(self.receipt(stage='ready', running=True, ready=True)['stage'], 'invalid_receipt')
        self.assertEqual(self.receipt(failure='none')['stage'], 'invalid_receipt')
        self.assertEqual(self.receipt(stage='ready', running=True, ready=True, failure='none')['stage'], 'ready')
        self.assertEqual(self.receipt(stage='failed', ready=True)['stage'], 'invalid_receipt')
        self.assertEqual(self.receipt(stage='ready', running=False, ready=True, failure='none')['stage'], 'invalid_receipt')

    def test_versions_and_numeric_booleans_are_rejected(self):
        for changes in [dict(schemaVersion=True), dict(schemaVersion=3), dict(running=1), dict(ready=0)]:
            self.assertEqual(self.receipt(**changes)['stage'], 'invalid_receipt')

    def test_expired_ready_receipt_cannot_claim_readiness(self):
        result = self.receipt(stage='ready', running=True, ready=True, failure='none', timestamp='2000-01-01T00:00:00Z')
        self.assertEqual(result, {'stage':'stale','ready':False})


if __name__ == '__main__':
    unittest.main()
