#!/usr/bin/env python3
"""Package selected project source and a verified public runtime, never user state."""
from pathlib import Path
import hashlib
import json
import tarfile

root = Path(__file__).resolve().parents[2]
selected = {root / p for p in (
    "AGENTS.md", "README.md", ".gitignore",
    "services/iris-mcp/package.json", "services/iris-mcp/package-lock.json",
    "services/iris-mcp/README.md",
    "policies/iris-connect-read-v1.draft.json", "policies/iris-connect-read-v1.approval.json",
    "build/tools/tunnel-client", "build/tools/LICENSE", "build/tools/NOTICE",
    "build/tools/tunnel-release-verified.json",
    "tools/iris-connect-status.py", "tools/iris-connect-read-status.py", "tools/iris-mcp-status.py",
    "tools/tests/test_iris_mcp_status.py",
    "tools/tests/test_mac_mini_startup.py", "tools/deployment/mac-mini-startup.py",
    "tools/deployment/mac-mini-preflight.sh", "tools/deployment/package-mac-mini.py",
)}
for directory, suffixes in (
    ("apps/iris-connect/Sources", {".swift"}),
    ("apps/iris-connect/Tests", {".swift"}),
    ("apps/iris-connect/scripts", {".sh"}),
    ("apps/iris-mcp-host/Sources", {".swift"}),
    ("apps/iris-mcp-host/Tests", {".swift"}),
    ("apps/iris-mcp-host/scripts", {".sh", ".py"}),
    ("services/iris-mcp/src", {".mjs"}),
    ("services/iris-mcp/test", {".mjs"}),
    ("services/iris-mcp/scripts", {".sh", ".sb", ".mjs"}),
    ("docs", {".md"}),
    ("integrations/aida", {".md", ".txt"}),
):
    selected.update(p for p in (root / directory).rglob("*") if p.suffix in suffixes)
selected.update(root / p for p in ("apps/iris-connect/Package.swift", "apps/iris-connect/README.md"))
manifest = []
for path in sorted(selected):
    if path.is_symlink() or not path.is_file() or not path.resolve().is_relative_to(root):
        raise SystemExit("Package rejected: invalid selected source path")
    manifest.append({"path": str(path.relative_to(root)), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
output = root / "build/mac-mini-source.tar.gz"
with tarfile.open(output, "w:gz") as archive:
    for path in sorted(selected):
        archive.add(path, arcname=str(path.relative_to(root)), recursive=False)
(root / "build/mac-mini-source-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
print(f"Packaged {len(manifest)} selected source/runtime files; no home directories or application state.")
