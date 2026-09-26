#!/usr/bin/env python3
"""Release metadata must fail before altering the bundle when input is unsafe."""
import base64
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parent.parent
valid = dict(feed_url='https://updates.example.org/appcast.xml', sparkle_public_key=base64.b64encode(bytes(range(32))).decode(), version='0.2.0', build=2)
invalid = [
    dict(feed_url='http://updates.example.org/appcast.xml'),
    dict(feed_url='https://secret@updates.example.org/appcast.xml'),
    dict(feed_url='https://updates.example.org/appcast.xml?token=private'),
    dict(feed_url='https://bad host/appcast.xml'),
    dict(sparkle_public_key=base64.b64encode(b'short').decode()),
    dict(version='../../escape'),
    dict(version=''),
    dict(build=0),
]
with tempfile.TemporaryDirectory(prefix='crest-release-tests-') as temporary:
    folder = Path(temporary)
    config_path, plist_path = folder/'config.json', folder/'Info.plist'
    for change in invalid:
        plist_path.write_bytes(plistlib.dumps({'Existing': 'preserved'}))
        before = plist_path.read_bytes()
        config_path.write_text(json.dumps(valid | change))
        result = subprocess.run([sys.executable, str(root/'scripts/configure-release.py'), str(config_path), str(plist_path)], capture_output=True)
        assert result.returncode != 0, change
        assert plist_path.read_bytes() == before, change
    config_path.write_text(json.dumps(valid))
    subprocess.run([sys.executable, str(root/'scripts/configure-release.py'), str(config_path), str(plist_path)], check=True)
    result = plistlib.loads(plist_path.read_bytes())
    assert result['Existing'] == 'preserved'
    assert result['CFBundleVersion'] == '2'
    assert result['CFBundleShortVersionString'] == '0.2.0'
    assert result['SUFeedURL'] == valid['feed_url']
print('PASS release configuration: 8 invalid inputs preserved the bundle; valid metadata applied')
