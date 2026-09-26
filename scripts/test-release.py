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
    assert result['SURequireSignedFeed'] is True
    assert result['SUVerifyUpdateBeforeExtraction'] is True
    assert result['SUEnableSystemProfiling'] is False
    archive = folder/'Crest-0.2.0.zip'
    archive.write_bytes(b'fixture')
    feed = folder/'appcast.xml'
    signature = base64.b64encode(bytes(64)).decode()
    def appcast(channel='', version='2', length=7, url='https://updates.example.org/Crest-0.2.0.zip', signed=True):
        return f'''<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
        <sparkle:version>{version}</sparkle:version>{f'<sparkle:channel>{channel}</sparkle:channel>' if channel else ''}
        <enclosure url="{url}" length="{length}" sparkle:edSignature="{signature if signed else ''}" />
        </item></channel></rss>'''
    cases = [(dict(), 'stable', True), (dict(channel='beta'), 'beta', True),
        (dict(channel='beta'), 'stable', False), (dict(version='1'), 'stable', False),
        (dict(length=99), 'stable', False), (dict(url='http://updates.example.org/Crest-0.2.0.zip'), 'stable', False),
        (dict(signed=False), 'stable', False)]
    for changes, channel, passes in cases:
        feed.write_text(appcast(**changes))
        completed = subprocess.run([sys.executable, str(root/'scripts/validate-appcast.py'), str(config_path), str(feed), str(folder), channel], capture_output=True)
        assert (completed.returncode == 0) == passes, changes
print('PASS release configuration: 8 invalid inputs preserved the bundle; valid metadata applied')
print('PASS appcast validation: stable/beta entries accepted; wrong channel/build/length, HTTP and missing signatures rejected')
