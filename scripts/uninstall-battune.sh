#!/bin/bash
# Explicit administrator operation: removes the Battune app, helper, launch
# daemon and installer receipts. Settings and history in the user's home
# folder are kept. Never called automatically by the app.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo 'Run with administrator authorization: sudo bash uninstall-battune.sh' >&2; exit 1; }
if pgrep -x Battune >/dev/null; then
  echo 'Quit Battune first (menu bar → Quit) so it can restore the native macOS limit.' >&2
  exit 1
fi
helper=/Library/PrivilegedHelperTools/BattuneHelper.app/Contents/MacOS/BattuneHelper
legacy=/Library/PrivilegedHelperTools/org.battune.helper
launchctl bootout system/org.battune.helper 2>/dev/null || true
# Restore adapter input owned by the helper before removing it; on failure keep
# the helper and its journal so an explicit retry remains possible.
if [[ -x "$helper" ]]; then "$helper" --restore-owned-state; fi
if [[ -x "$legacy" ]]; then "$legacy" --restore-owned-state; fi
if [[ -e '/Library/Application Support/BattuneHelper/adapter-owned' ]]; then
  echo 'Adapter recovery is not confirmed. Nothing was removed.' >&2
  exit 1
fi
rm -rf /Library/PrivilegedHelperTools/BattuneHelper.app /Applications/Battune.app
rm -f "$legacy" /Library/LaunchDaemons/org.battune.helper.plist
rm -rf '/Library/Application Support/BattuneHelper'
for receipt in org.battune.beta org.battune.helper.local; do
  pkgutil --forget "$receipt" >/dev/null 2>&1 || true
done
echo 'Battune app and helper removed. Settings and history in ~/Library were kept.'
