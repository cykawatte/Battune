#!/bin/bash
# Explicit administrator operation; never called automatically by the app.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo 'Run with administrator authorization after disabling Battune control and quitting the app.' >&2; exit 1; }
helper=/Library/PrivilegedHelperTools/org.battune.helper
launchctl bootout system/org.battune.helper 2>/dev/null || true
# On failed recovery, retain the executable and journal for an explicit retry.
if [[ -x "$helper" ]]; then "$helper" --restore-owned-state; fi
if [[ -e '/Library/Application Support/BattuneHelper/adapter-owned' ]]; then
  echo 'Recovery is not confirmed. Helper files have been retained.' >&2
  exit 1
fi
rm -f "$helper" /Library/LaunchDaemons/org.battune.helper.plist '/Library/Application Support/BattuneHelper/identity.json'
rmdir '/Library/Application Support/BattuneHelper' 2>/dev/null || true
pkgutil --forget org.battune.helper.local >/dev/null 2>&1 || true
echo 'Local helper removed after recovery. Native macOS limits are restored by quitting Battune normally.'
