#!/bin/bash
# Inspect the distributable without installing or running privileged code.
set -euo pipefail
cd "$(dirname "$0")/.."
version="$(cat VERSION)"
review="$(mktemp -d "$PWD/build/package-review.XXXXXX")"
trap 'rm -rf "$review"' EXIT
(cd build/packages && shasum -a 256 -c SHA256SUMS.txt)
for mode in full helper; do
  package="build/packages/Battune-$version.pkg"
  [[ "$mode" != helper ]] || package="build/packages/BattuneHelper-$version.pkg"
  pkgutil --expand-full "$package" "$review/$mode"
done
python3 - "$review" "$version" <<'PY'
import json, pathlib, plistlib, re, subprocess, sys, xml.etree.ElementTree as ET
review = pathlib.Path(sys.argv[1]); version = sys.argv[2]
def plist(path):
    with path.open('rb') as f: return plistlib.load(f)
def hashes(executable):
    arches = subprocess.check_output(['lipo', '-archs', str(executable)], text=True).split()
    assert set(arches) == {'arm64', 'x86_64'}, arches
    result = []
    for arch in arches:
        info = subprocess.run(['codesign', '-d', '--verbose=4', '--arch', arch, str(executable)], capture_output=True, text=True, check=True)
        result.append(re.search(r'^CDHash=([a-f0-9]{40})$', info.stderr, re.M).group(1))
    return set(result)
def bundle(path, identifier):
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(path)], check=True)
    info = plist(path/'Contents/Info.plist')
    assert info['CFBundleIdentifier'] == identifier
    assert (path/'Contents/Resources'/ (info['CFBundleIconFile'] + '.icns')).stat().st_size > 1000
    return path/'Contents/MacOS'/info['CFBundleExecutable']
app = review/'full/component.pkg/Payload/Applications/Battune.app'
app_hashes = hashes(bundle(app, 'org.battune.app'))
assert plist(app/'Contents/Info.plist')['BattuneDevelopmentVersion'] == version
embedded_hashes = hashes(bundle(app/'Contents/Library/HelperTools/BattuneHelper.app', 'org.battune.helper'))
for mode in ('full', 'helper'):
    component = review/mode/'component.pkg'
    payload = component/'Payload'
    helper = payload/'Library/PrivilegedHelperTools/BattuneHelper.app'
    trust = json.loads((payload/'Library/Application Support/BattuneHelper/identity.json').read_text())
    assert set(trust['applicationHashes']) == app_hashes
    assert set(trust['helperHashes']) == hashes(bundle(helper, 'org.battune.helper')) == embedded_hashes
    daemon = plist(payload/'Library/LaunchDaemons/org.battune.helper.plist')
    assert daemon['ProgramArguments'] == ['/Library/PrivilegedHelperTools/BattuneHelper.app/Contents/MacOS/BattuneHelper']
    assert daemon['MachServices'] == {'org.battune.helper': True}
    assert set(daemon['AssociatedBundleIdentifiers']) == {'org.battune.app', 'org.battune.helper'}
    info = ET.parse(component/'PackageInfo').getroot()
    assert info.attrib['auth'] == 'root' and info.attrib['relocatable'] == 'false'
    assert len(info.find('relocate')) == 0
    assert '--restore-owned-state' in (component/'Scripts/preinstall').read_text()
    assert 'launchctl bootstrap' in (component/'Scripts/postinstall').read_text()
    assert 'Battune' in (review/mode/'Resources/welcome.html').read_text()
    if mode == 'full': assert 'pgrep -x Battune' in (component/'Scripts/preinstall').read_text()
    else: assert not (payload/'Applications').exists()
print('Verified universal app/helper signatures, exact-hash pairing, icons, fixed install paths, recovery scripts and checksums.')
PY
