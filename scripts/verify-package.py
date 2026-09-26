#!/usr/bin/env python3
"""Validate the deliverable after extraction and emit its SHA-256 manifest."""
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import zipfile

archive = Path(sys.argv[1]).resolve()
with zipfile.ZipFile(archive) as package:
    for entry in package.infolist():
        path = Path(entry.filename)
        if path.is_absolute() or '..' in path.parts:
            raise SystemExit('Unsafe archive path')
with tempfile.TemporaryDirectory(prefix='crest-package-check-') as temporary:
    subprocess.run(['ditto', '-x', '-k', str(archive), temporary], check=True)
    app = Path(temporary)/'Crest.app'
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    info = plistlib.loads((app/'Contents/Info.plist').read_bytes())
    assert info['CFBundleIdentifier'] == 'app.crest.mac', 'Unexpected bundle identity'
    assert info['CFBundleVersion'].isdigit(), 'Invalid build'
    for document in ['Privacy', 'Uninstall', 'ThirdPartyNotices']:
        assert (app/f'Contents/Resources/{document}.txt').stat().st_size > 100, f'Missing {document}'
    executable = app/'Contents/MacOS/Crest'
    helper = app/'Contents/Helpers/crest-bridge'
    arch = subprocess.check_output(['lipo', '-archs', str(executable)], text=True).strip()
    helper_arch = subprocess.check_output(['lipo', '-archs', str(helper)], text=True).strip()
    assert arch == helper_arch, 'Helper architecture differs'
    assert (app/'Contents/Frameworks/Sparkle.framework/Sparkle').exists(), 'Sparkle missing'
    signature = subprocess.run(['codesign', '-dv', str(app)], capture_output=True, text=True, check=True).stderr
    manifest = dict(schema_version=1, archive=archive.name, bytes=archive.stat().st_size,
        sha256=hashlib.sha256(archive.read_bytes()).hexdigest(), bundle_id=info['CFBundleIdentifier'],
        version=info['CFBundleShortVersionString'], build=info['CFBundleVersion'], architectures=arch.split(),
        executable_sha256=hashlib.sha256(executable.read_bytes()).hexdigest(),
        minimum_macos=info['LSMinimumSystemVersion'], ad_hoc_signed='Signature=adhoc' in signature,
        update_feed_configured=bool(info.get('SUFeedURL')))
archive.with_suffix('.manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
archive.with_suffix('.sha256').write_text(f"{manifest['sha256']}  {archive.name}\n")
print(f"PASS extracted {manifest['version']} ({manifest['build']}): signature, helper, resources, architecture; checksum emitted")
