#!/bin/bash
# Build only. Installing either package always requires administrator approval.
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-release}"
mode="${2:-helper}"
case "$configuration" in debug|release) ;; *) exit 2;; esac
case "$mode" in helper|full) ;; *) exit 2;; esac
version="$(cat VERSION)"
app="$PWD/build/$configuration/Battune.app"
helper="$app/Contents/Library/HelperTools/BattuneHelper.app"
[[ -f "$helper/Contents/MacOS/BattuneHelper" ]] || { echo 'Build the app first.' >&2; exit 1; }
codesign --verify --deep --strict "$app"
staging="$(mktemp -d "$PWD/build/helper-installer.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
root="$staging/root"
mkdir -p "$root/Library/PrivilegedHelperTools" "$root/Library/LaunchDaemons" "$root/Library/Application Support/BattuneHelper" "$staging/scripts" "$staging/resources"
chmod 1755 "$root/Library/PrivilegedHelperTools"
ditto "$helper" "$root/Library/PrivilegedHelperTools/BattuneHelper.app"
if [[ "$mode" == full ]]; then
  mkdir -p "$root/Applications"
  ditto "$app" "$root/Applications/Battune.app"
fi
python3 - "$app" "$helper" "$root" <<'PY'
import json, pathlib, plistlib, re, subprocess, sys
app, helper, root = sys.argv[1:]
def hashes(path):
    result=[]
    for arch in subprocess.check_output(['lipo','-archs',path], text=True).split():
        info=subprocess.run(['codesign','-d','--verbose=4','--arch',arch,path],text=True,capture_output=True,check=True)
        result.append(re.search(r'^CDHash=([a-f0-9]{40})$',info.stderr,re.M).group(1))
    return result
base=pathlib.Path(root)/'Library'
(base/'Application Support/BattuneHelper/identity.json').write_text(json.dumps({
 'applicationHashes':hashes(app+'/Contents/MacOS/Battune'),
 'helperHashes':hashes(helper+'/Contents/MacOS/BattuneHelper')}))
with (base/'LaunchDaemons/org.battune.helper.plist').open('wb') as f:
 plistlib.dump({'Label':'org.battune.helper',
 'ProgramArguments':['/Library/PrivilegedHelperTools/BattuneHelper.app/Contents/MacOS/BattuneHelper'],
 'AssociatedBundleIdentifiers':['org.battune.app','org.battune.helper'],
 'MachServices':{'org.battune.helper':True},'RunAtLoad':True,'KeepAlive':True,'ProcessType':'Background'},f)
PY
cat > "$staging/scripts/preinstall" <<'PRE'
#!/bin/bash
set -euo pipefail
launchctl bootout system/org.battune.helper 2>/dev/null || true
# Restore with the existing helper before replacing it. Failure aborts the upgrade.
for helper in /Library/PrivilegedHelperTools/BattuneHelper.app/Contents/MacOS/BattuneHelper /Library/PrivilegedHelperTools/org.battune.helper; do
  if [[ -x "$helper" ]]; then "$helper" --restore-owned-state; fi
done
PRE
if [[ "$mode" == full ]]; then
  python3 - "$staging/scripts/preinstall" <<'PY'
import pathlib,sys
p=pathlib.Path(sys.argv[1]);s=p.read_text().replace('launchctl bootout', '''# Quit the app normally first, so its native ownership journal is restored.
if pgrep -x Battune >/dev/null; then
  echo 'Please quit Battune before installing this update.' >&2
  exit 1
fi
launchctl bootout''',1);p.write_text(s)
PY
fi
cat > "$staging/scripts/postinstall" <<'POST'
#!/bin/bash
set -euo pipefail
chown -R root:wheel '/Library/Application Support/BattuneHelper' /Library/PrivilegedHelperTools/BattuneHelper.app
chmod 755 '/Library/Application Support/BattuneHelper'
chmod 644 '/Library/Application Support/BattuneHelper/identity.json'
chown root:wheel /Library/LaunchDaemons/org.battune.helper.plist
chmod 644 /Library/LaunchDaemons/org.battune.helper.plist
# Remove only the former, fixed-path development executable after successful recovery.
rm -f /Library/PrivilegedHelperTools/org.battune.helper
launchctl bootstrap system /Library/LaunchDaemons/org.battune.helper.plist
POST
chmod 755 "$staging/scripts/"*
xattr -cr "$root"
pkgbuild --analyze --root "$root" "$staging/components.plist"
python3 - "$staging/components.plist" <<'PY'
import plistlib,sys
p=sys.argv[1]
with open(p,'rb') as f: components=plistlib.load(f)
for component in components:
 component['BundleIsRelocatable']=False
 component['BundleOverwriteAction']='upgrade'
with open(p,'wb') as f: plistlib.dump(components,f)
PY
identifier=org.battune.helper.local
output="$PWD/build/$configuration/BattuneHelper.pkg"
if [[ "$mode" == full ]]; then identifier=org.battune.beta; output="$PWD/build/$configuration/Battune-$version.pkg"; fi
pkgbuild --root "$root" --component-plist "$staging/components.plist" --scripts "$staging/scripts" \
  --identifier "$identifier" --version 0.1.0.4 --install-location / "$staging/component.pkg"
cp packaging/installer-welcome.html "$staging/resources/welcome.html"
python3 - "$staging/distribution.xml" "$identifier" <<'PY'
import pathlib,sys
p,identifier=sys.argv[1:]
pathlib.Path(p).write_text(f'''<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
<title>Battune Beta</title>
<welcome file="welcome.html" mime-type="text/html"/>
<options customize="never" require-scripts="false" hostArchitectures="arm64,x86_64"/>
<domains enable_localSystem="true" enable_currentUserHome="false" enable_anywhere="false"/>
<allowed-os-versions><os-version min="13.0"/></allowed-os-versions>
<choices-outline><line choice="default"/></choices-outline>
<choice id="default" visible="false"><pkg-ref id="{identifier}"/></choice>
<pkg-ref id="{identifier}" version="0.1.0.4" auth="Root">component.pkg</pkg-ref>
</installer-gui-script>''')
PY
productbuild --distribution "$staging/distribution.xml" --resources "$staging/resources" --package-path "$staging" "$output"
echo "Prepared $output — no system installation performed."
