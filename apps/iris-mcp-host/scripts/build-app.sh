#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
TASK_APP="$TASK_ROOT/build/Iris MCP.app"
if [ "${1:-}" = "--stage" ]; then
  mkdir -p "$TASK_ROOT/build"
  TASK_STAGE="$(mktemp -d "$TASK_ROOT/build/staging-mcp.XXXXXX")"
  TASK_APP="$TASK_STAGE/Iris MCP.app"
elif [ "$#" -ne 0 ]; then
  exit 1
elif pgrep -x IrisMCPHost >/dev/null; then
  printf '%s\n' 'Iris MCP běží. Před sestavením jej bezpečně ukonči.' >&2;exit 1
fi
mkdir -p "$TASK_APP/Contents/MacOS" "$TASK_APP/Contents/Resources" "$TASK_ROOT/build/module-cache"
CLANG_MODULE_CACHE_PATH="$TASK_ROOT/build/module-cache" swiftc -parse-as-library -O \
  -target "$(/usr/bin/uname -m)-apple-macos14.0" \
  -module-cache-path "$TASK_ROOT/build/module-cache" \
  "$TASK_ROOT/apps/iris-mcp-host/Sources/TunnelPolicy.swift" "$TASK_ROOT/apps/iris-mcp-host/Sources/WorkerLifecycle.swift" "$TASK_ROOT/apps/iris-mcp-host/Sources/Main.swift" \
  -o "$TASK_APP/Contents/MacOS/IrisMCPHost"
cp "$TASK_ROOT/build/tools/tunnel-client" "$TASK_APP/Contents/MacOS/tunnel-client"
cat > "$TASK_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>net.iris.mcp-host.local</string>
<key>CFBundleName</key><string>Iris MCP</string>
<key>CFBundleExecutable</key><string>IrisMCPHost</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2.1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --sign - --options runtime --timestamp=none "$TASK_APP/Contents/MacOS/tunnel-client"
codesign --force --sign - --options runtime --timestamp=none "$TASK_APP"
codesign --verify --strict "$TASK_APP"
printf '%s\n' "$TASK_APP"
