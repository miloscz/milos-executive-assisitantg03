#!/bin/bash
# Read-only, fixed host facts only. No Keychain, shell profiles, env dumps, credentials or logs.
set -u
printf 'macos='; /usr/bin/sw_vers -productVersion
printf 'arch='; /usr/bin/uname -m
printf 'uid='; /usr/bin/id -u
printf 'consoleUser='; /usr/bin/stat -f '%Su' /dev/console
if /bin/launchctl print "gui/$(/usr/bin/id -u)" >/dev/null 2>&1; then printf 'guiSession=yes\n'; else printf 'guiSession=no\n'; fi
if /usr/bin/xcode-select -p >/dev/null 2>&1; then printf 'developerTools=yes\n'; else printf 'developerTools=no\n'; fi
for task_node in /opt/homebrew/bin/node /usr/local/bin/node; do
  if [ -x "$task_node" ]; then printf 'node='; "$task_node" --version; break; fi
done
for task_codex in /opt/homebrew/bin/codex /usr/local/bin/codex /Applications/Codex.app/Contents/MacOS/Codex; do
  if [ -x "$task_codex" ]; then printf 'codexInstalled=yes\n'; break; fi
done
printf 'power='; /usr/bin/pmset -g custom | /usr/bin/awk '$1 == "sleep" {print $2; exit}'
