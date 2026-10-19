#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TASK_REPO="$(cd "$TASK_ROOT/../.." && pwd)"
TASK_APP="$TASK_REPO/build/Iris Connect.app"
# Refuse to replace a bundle that may be displaying credentials or running MFA.
if [ "${1:-}" = "--stage" ]; then
  mkdir -p "$TASK_REPO/build"
  TASK_STAGE="$(mktemp -d "$TASK_REPO/build/staging.XXXXXX")"
  TASK_APP="$TASK_STAGE/Iris Connect.app"
elif [ "$#" -ne 0 ]; then
  exit 1
elif pgrep -x IrisConnect >/dev/null; then
  printf '%s\n' 'Iris Connect běží. Před sestavením aplikaci bezpečně ukonči.' >&2
  exit 1
fi
cd "$TASK_ROOT"
export CLANG_MODULE_CACHE_PATH="$TASK_REPO/build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$TASK_REPO/build/module-cache"
swift build --disable-sandbox -c release --scratch-path "$TASK_REPO/build/swift" \
  -Xswiftc -module-cache-path -Xswiftc "$TASK_REPO/build/module-cache"
TASK_BIN="$(swift build --disable-sandbox -c release --scratch-path "$TASK_REPO/build/swift" --show-bin-path)"
mkdir -p "$TASK_APP/Contents/MacOS" "$TASK_APP/Contents/Resources"
cp "$TASK_BIN/IrisConnect" "$TASK_APP/Contents/MacOS/IrisConnect"
cp "$TASK_BIN/IrisRead" "$TASK_APP/Contents/MacOS/IrisRead"
cp "$TASK_BIN/IrisControl" "$TASK_APP/Contents/MacOS/IrisControl"
cp "$TASK_REPO/policies/iris-connect-read-v1.draft.json" "$TASK_APP/Contents/Resources/iris-connect-read-v1.json"
cp "$TASK_REPO/policies/iris-connect-briefing-sources-v1.draft.json" "$TASK_APP/Contents/Resources/iris-connect-briefing-sources-v1.json"
codesign --force --sign - --identifier net.iris.connect.read-client --options runtime --timestamp=none "$TASK_APP/Contents/MacOS/IrisRead"
codesign --force --sign - --identifier net.iris.connect.auth-client --options runtime --timestamp=none "$TASK_APP/Contents/MacOS/IrisControl"
/usr/libexec/PlistBuddy -c 'Clear dict' "$TASK_APP/Contents/Info.plist" >/dev/null 2>&1 || true
cat > "$TASK_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>net.iris.connect.local-prototype</string>
<key>CFBundleName</key><string>Iris Connect</string>
<key>CFBundleDisplayName</key><string>Iris Connect</string>
<key>CFBundleExecutable</key><string>IrisConnect</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.8.0</string>
<key>CFBundleVersion</key><string>20</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSSupportsAutomaticTermination</key><false/>
<key>NSSupportsSuddenTermination</key><false/>
</dict></plist>
PLIST
# Local ad-hoc signature, hardened runtime, no debugger entitlement and no library-validation exceptions.
codesign --force --sign - --options runtime --timestamp=none "$TASK_APP"
codesign --verify --strict "$TASK_APP"
printf '%s\n' "$TASK_APP"
