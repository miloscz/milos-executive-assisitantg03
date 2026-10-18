#!/usr/bin/env python3
"""Download only the official release; verify GitHub's published SHA-256 before extraction."""
import hashlib
import io
import json
import platform
from pathlib import Path
import urllib.request
import zipfile

root = Path(__file__).resolve().parents[3]
architecture = {'arm64':'arm64', 'x86_64':'amd64'}.get(platform.machine())
if platform.system() != 'Darwin' or not architecture:
    raise SystemExit('Unsupported platform')
with urllib.request.urlopen('https://api.github.com/repos/openai/tunnel-client/releases/latest', timeout=30) as response:
    release = json.load(response)
version = release['tag_name']
expected_name = f'tunnel-client-{version}-darwin-{architecture}.zip'
asset = next(a for a in release['assets'] if a['name'] == expected_name)
url = asset['browser_download_url']
if not url.startswith('https://github.com/openai/tunnel-client/releases/download/'):
    raise SystemExit('Untrusted download URL')
digest = asset.get('digest', '')
if not digest.startswith('sha256:') or len(digest) != 71:
    raise SystemExit('Missing official SHA-256')
with urllib.request.urlopen(url, timeout=60) as response:
    payload = response.read(200_000_001)
if len(payload) > 200_000_000 or hashlib.sha256(payload).hexdigest() != digest[7:]:
    raise SystemExit('Release verification failed')
destination = root/'build/tools'
destination.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(io.BytesIO(payload)) as archive:
    for name in ['tunnel-client', 'LICENSE', 'NOTICE']:
        info = archive.getinfo(name)
        if info.file_size > 200_000_000:
            raise SystemExit('Oversized archive item')
        (destination/name).write_bytes(archive.read(name))
(destination/'tunnel-client').chmod(0o755)
(destination/'tunnel-release-verified.json').write_text(json.dumps({'version':version,'asset':expected_name,'sha256':digest[7:]}))
print(f'Official tunnel-client {version}: SHA-256 verified')
