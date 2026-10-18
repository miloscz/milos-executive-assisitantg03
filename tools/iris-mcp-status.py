#!/usr/bin/env python3
"""Only fixed transport health flags. Never read a key, configuration, URL or log."""
import json
import os
import stat
from datetime import datetime, timezone
from pathlib import Path

FAILURES = {
    'none', 'invalidTunnelID', 'invalidRuntimeKey', 'appIntegrity', 'keyMissing', 'storedKeyInvalid',
    'keychainSave', 'keychainRead', 'keychainDenied', 'keychainCancelled', 'keychainInteraction',
    'keychainUnavailable', 'keychainParameters', 'launcherMissing', 'clientMissing', 'nodeMissing',
    'configurationWrite', 'clientLaunch', 'clientExited',
}


def read_status():
    folder = Path.home() / 'Library/Application Support/Iris MCP'
    path = folder / 'verification.json'
    if not path.exists():
        return {'stage': 'receipt_missing', 'ready': False}
    if folder.is_symlink() or path.is_symlink():
        return {'stage': 'invalid_receipt', 'ready': False}
    info = path.stat()
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_size > 4096:
        return {'stage': 'invalid_receipt', 'ready': False}
    data = json.loads(path.read_text())
    if not isinstance(data, dict) or type(data.get('schemaVersion')) is not int:
        return {'stage': 'invalid_receipt', 'ready': False}
    expected = {'schemaVersion','stage','running','ready','timestamp'}
    if data['schemaVersion'] == 2:
        expected.add('failure')
    elif data['schemaVersion'] != 1:
        return {'stage': 'invalid_receipt', 'ready': False}
    if set(data) != expected or data['stage'] not in {'stopped','starting','ready','failed'}:
        return {'stage': 'invalid_receipt', 'ready': False}
    failure = data.get('failure', 'none')
    if type(failure) is not str or failure not in FAILURES:
        return {'stage': 'invalid_receipt', 'ready': False}
    if (data['stage'] == 'failed') != (failure != 'none') and data['schemaVersion'] == 2:
        return {'stage': 'invalid_receipt', 'ready': False}
    if any(type(data[x]) is not bool for x in ('running','ready')):
        return {'stage': 'invalid_receipt', 'ready': False}
    if (data['stage'] == 'ready') != data['ready'] or (data['ready'] and not data['running']):
        return {'stage': 'invalid_receipt', 'ready': False}
    if not isinstance(data['timestamp'], str) or len(data['timestamp']) > 40:
        return {'stage': 'invalid_receipt', 'ready': False}
    moment = datetime.fromisoformat(data['timestamp'].replace('Z','+00:00'))
    if moment.tzinfo is None:
        return {'stage': 'invalid_receipt', 'ready': False}
    age = (datetime.now(timezone.utc)-moment).total_seconds()
    if age < -5 or (age > 15 and data['stage'] in {'ready','starting'}):
        return {'stage': 'stale', 'ready': False}
    result = {'stage':data['stage'],'running':data['running'],'ready':data['ready'],'timestamp':moment.isoformat()}
    if data['schemaVersion'] == 2:
        result['failure'] = failure
    return result

if __name__ == '__main__':
    try:
        print(json.dumps(read_status(), ensure_ascii=False))
    except (OSError, ValueError, TypeError, KeyError):
        print('{"stage":"invalid_receipt","ready":false}')
