#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-release}"
case "$configuration" in debug|release) ;; *) exit 2;; esac
app="$PWD/build/$configuration/Battune.app"
helper="$app/Contents/Library/HelperTools/BattuneHelper"
[[ -f "$helper" ]] || { echo 'Build the app first.' >&2; exit 1; }
codesign --verify --deep --strict "$app"
staging="$(mktemp -d "$PWD/build/helper-installer.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
root="$staging/root"
mkdir -p "$root/Library/PrivilegedHelperTools" "$root/Library/LaunchDaemons" "$root/Library/Application Support/BattuneHelper" "$staging/scripts"
chmod 1755 "$root/Library/PrivilegedHelperTools"
cp "$helper" "$root/Library/PrivilegedHelperTools/org.battune.helper"
python3 - "$app" "$helper" "$root" <<'PY'
import json, pathlib, plistlib, re, subprocess, sys
app, helper, root = sys.argv[1:]
def hashes(path):
    archs = subprocess.check_output(['lipo','-archs',path], text=True).split()
    result=[]
    for arch in archs:
        info=subprocess.run(['codesign','-d','--verbose=4','--arch',arch,path],text=True,capture_output=True,check=True)
        result.append(re.search(r'^CDHash=([a-f0-9]{40})$',info.stderr,re.M).group(1))
    return result
base=pathlib.Path(root)/'Library'
(base/'Application Support/BattuneHelper/identity.json').write_text(json.dumps({
 'applicationHashes':hashes(app+'/Contents/MacOS/Battune'), 'helperHashes':hashes(helper)}))
with (base/'LaunchDaemons/org.battune.helper.plist').open('wb') as f:
 plistlib.dump({'Label':'org.battune.helper', 'ProgramArguments':['/Library/PrivilegedHelperTools/org.battune.helper'],
 'MachServices':{'org.battune.helper':True},'RunAtLoad':True,'KeepAlive':True,'ProcessType':'Background'},f)
PY
cat > "$staging/scripts/preinstall" <<'SH'
#!/bin/bash
set -euo pipefail
# Stop the daemon first so it cannot race restoration or replacement.
launchctl bootout system/org.battune.helper 2>/dev/null || true
# Recover owned adapter state before replacing the helper.
if [[ -x /Library/PrivilegedHelperTools/org.battune.helper ]]; then
  /Library/PrivilegedHelperTools/org.battune.helper --restore-owned-state
fi
SH
cat > "$staging/scripts/postinstall" <<'SH'
#!/bin/bash
set -euo pipefail
chown -R root:wheel '/Library/Application Support/BattuneHelper'
chmod 755 '/Library/Application Support/BattuneHelper'
chmod 644 '/Library/Application Support/BattuneHelper/identity.json'
chown root:wheel /Library/PrivilegedHelperTools/org.battune.helper /Library/LaunchDaemons/org.battune.helper.plist
chmod 755 /Library/PrivilegedHelperTools/org.battune.helper
chmod 644 /Library/LaunchDaemons/org.battune.helper.plist
launchctl bootstrap system /Library/LaunchDaemons/org.battune.helper.plist
SH
chmod 755 "$staging/scripts/"*
# Payload metadata is explicit; omit inherited extended attributes/resource forks.
xattr -cr "$root"
pkgbuild --root "$root" --scripts "$staging/scripts" --identifier org.battune.helper.local \
  --version 0.1.0 --install-location / "$PWD/build/$configuration/BattuneHelper.pkg"
echo 'Installer prepared only. No helper has been installed or enabled.'
