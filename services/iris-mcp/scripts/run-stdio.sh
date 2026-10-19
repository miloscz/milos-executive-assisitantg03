#!/bin/bash
set -euo pipefail
unset CONTROL_PLANE_API_KEY OPENAI_API_KEY
TASK_SERVICE="$(cd "$(dirname "$0")/.." && pwd)"
TASK_REPO="$(cd "$TASK_SERVICE/../.." && pwd)"
TASK_NODE=""
for task_candidate in /opt/homebrew/bin/node /usr/local/bin/node; do
  if [ -x "$task_candidate" ]; then TASK_NODE="$task_candidate"; break; fi
done
if [ -z "$TASK_NODE" ]; then exit 1; fi
# Empty environment: in particular, a tunnel runtime key must not reach the MCP server.
exec /usr/bin/env -i HOME="$HOME" PATH=/usr/bin:/bin \
  /usr/bin/sandbox-exec \
  -D "USER_HOME=$HOME" \
  -D "SERVICE_ROOT=$TASK_SERVICE" \
  -D "APP_BUNDLE=$TASK_REPO/build/Iris Connect.app" \
  -D "AUTH_DIRECTORY=$HOME/Library/Application Support/Iris Connect" \
  -D "AUTH_SOCKET=$HOME/Library/Application Support/Iris Connect/auth.sock" \
  -D "BRIEFING_FILE=$TASK_REPO/.iris-runtime/morning-briefing.json" \
  -D "WORK_SOCKET=$TASK_REPO/.iris-runtime/w.sock" \
  -D "DETAIL_FILE=$TASK_REPO/.iris-runtime/briefing-details.json" \
  -D "HELPER=$TASK_REPO/build/Iris Connect.app/Contents/MacOS/IrisControl" \
  -D "NODE_BINARY=$TASK_NODE" \
  -f "$TASK_SERVICE/scripts/bridge.sb" \
  "$TASK_NODE" "$TASK_SERVICE/src/main.mjs"
