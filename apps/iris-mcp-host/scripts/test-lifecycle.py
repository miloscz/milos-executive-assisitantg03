#!/usr/bin/env python3
"""Synthetic lifecycle: no real tunnel, API, Keychain or user credentials."""
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time

repo = Path(__file__).resolve().parents[3]
cache = repo / 'build/module-cache'
cache.mkdir(parents=True, exist_ok=True)


def gone(pid):
    result = subprocess.run(['/bin/ps', '-p', str(pid), '-o', 'stat='], text=True, capture_output=True, check=False)
    return result.returncode != 0 or result.stdout.strip().startswith('Z')


with tempfile.TemporaryDirectory(prefix='iris-synthetic-lifecycle-') as temporary:
    folder = Path(temporary)
    binary, lease = folder / 'fixture', folder / 'lease'
    subprocess.run(['/usr/bin/swiftc', '-parse-as-library', '-module-cache-path', str(cache),
                    str(repo / 'apps/iris-mcp-host/Sources/WorkerLifecycle.swift'),
                    str(repo / 'apps/iris-mcp-host/Tests/LifecycleFixture.swift'), '-o', str(binary)], check=True)
    for sig in [signal.SIGTERM, signal.SIGINT]:
        fixture = subprocess.Popen([str(binary), str(lease)], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        worker = child = None
        try:
            worker, child = map(int, fixture.stdout.readline().split())
            # A second process cannot acquire the same lease.
            duplicate = subprocess.run([str(binary), str(lease)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
            if duplicate.returncode != 2:
                raise SystemExit('Duplicate host lease was not rejected')
            fixture.send_signal(sig)
            if fixture.wait(timeout=5) != 0:
                raise SystemExit('Graceful signal cleanup failed')
            deadline = time.monotonic() + 3
            while time.monotonic() < deadline and not all(gone(pid) for pid in [worker, child]):
                time.sleep(.05)
            if not all(gone(pid) for pid in [worker, child]):
                raise SystemExit('Synthetic worker group survived host termination')
        finally:
            if fixture.poll() is None:
                fixture.kill(); fixture.wait()
            if worker is not None and not gone(worker):
                os.killpg(worker, signal.SIGKILL)
    print('Lifecycle passed: TERM/INT stop worker and child; duplicates rejected; lease reacquired after exit.')
