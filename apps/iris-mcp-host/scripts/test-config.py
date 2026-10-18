#!/usr/bin/env python3
"""Validate generated YAML with the official client, using only synthetic data.

Never opens the installed app's configuration, Keychain, logs or environment.
The client runs doctor (no daemon), with an empty temporary home, a fake key,
and the control-plane URL overridden to an unreachable loopback endpoint.
"""
import json
from pathlib import Path
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[3]
cache = repo / 'build/module-cache'
cache.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='iris-synthetic-config-') as tmp:
    folder = Path(tmp)
    fixture = folder / 'fixture'
    subprocess.run([
        '/usr/bin/swiftc', '-parse-as-library', '-module-cache-path', str(cache),
        str(repo / 'apps/iris-mcp-host/Sources/TunnelPolicy.swift'),
        str(repo / 'apps/iris-mcp-host/Tests/ConfigFixture.swift'), '-o', str(fixture),
    ], check=True)
    config = subprocess.check_output([str(fixture)], text=True)
    # Exercise the actual generated command's quoting, replacing only the test path.
    script = folder / 'path with space' / 'run-stdio.sh'
    script.parent.mkdir()
    script.write_text('#!/bin/bash\nexit 0\n')
    script.chmod(0o700)
    config = config.replace('/synthetic/path with space/run-stdio.sh', str(script))
    path = folder / 'synthetic.yaml'
    path.write_text(config)
    args = [
        str(repo / 'build/tools/tunnel-client'), 'doctor', '--config', str(path),
        '--control-plane.base-url', 'http://127.0.0.1:1', '--json',
        '--mcp.max-concurrent-requests', '2', '--control-plane.max-inflight', '2',
        '--mcp.stdio-send-initialized-notification',
    ]
    env = {'HOME': tmp, 'PATH': '/usr/bin:/bin',
           'CONTROL_PLANE_API_KEY': 'sk-SYNTHETIC_ONLY_123456789'}
    result = subprocess.run(args, env=env, capture_output=True, text=True, timeout=20)
    report = json.loads(result.stdout)
    # No raw diagnostic text: only test outcome; all inputs are synthetic anyway.
    if result.returncode != 0 or report.get('result') != 'ok':
        raise SystemExit('Synthetic generated configuration failed official doctor')
    # Reproduce the original bug to prove the regression test catches it.
    path.write_text(config.replace('/bin/bash', '\\/bin\\/bash'))
    broken = subprocess.run(args, env=env, capture_output=True, text=True, timeout=20)
    rejected = json.loads(broken.stdout)
    if broken.returncode != 2 or 'profile_load' not in rejected.get('failed_checks', []):
        raise SystemExit('Official doctor did not reject the legacy slash escaping')
    print('Generated YAML: official tunnel-client doctor passed; synthetic inputs only')
    print('Regression: legacy slash escaping rejected as expected')
