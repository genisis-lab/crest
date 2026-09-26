#!/usr/bin/env python3
"""Validate a locally generated feed against the current release configuration."""
import base64
import json
from pathlib import Path
import sys
from urllib.parse import unquote, urlsplit
import xml.etree.ElementTree as ET

config = json.loads(Path(sys.argv[1]).read_text())
feed = Path(sys.argv[2])
archives = Path(sys.argv[3])
expected_channel = sys.argv[4] if len(sys.argv) > 4 else 'stable'
namespace = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
root = ET.fromstring(feed.read_bytes())
matched = []
for item in root.findall('./channel/item'):
    version = item.findtext(namespace+'version')
    enclosure = item.find('enclosure')
    if enclosure is None:
        raise SystemExit('Missing update enclosure')
    version = version or enclosure.get(namespace+'version')
    url = urlsplit(enclosure.get('url', ''))
    if url.scheme != 'https' or not url.hostname or url.username or url.password or url.query or url.fragment:
        raise SystemExit('Update enclosure must be plain HTTPS')
    try:
        signature = base64.b64decode(enclosure.get(namespace+'edSignature', ''), validate=True)
    except ValueError as error:
        raise SystemExit('Invalid update signature encoding') from error
    if len(signature) != 64:
        raise SystemExit('Missing Ed25519 update signature')
    if version == str(config['build']):
        matched.append(item)
        channel = item.findtext(namespace+'channel') or 'stable'
        if channel != expected_channel:
            raise SystemExit('Release channel mismatch')
        name = unquote(url.path.rsplit('/', 1)[-1])
        if '/' in name or '\\' in name or name in ('.', '..'):
            raise SystemExit('Unsafe archive filename')
        archive = archives/name
        if not archive.is_file() or archive.stat().st_size != int(enclosure.get('length', '-1')):
            raise SystemExit('Archive missing or length mismatch')
if len(matched) != 1:
    raise SystemExit('Expected exactly one entry for the current build')
print('PASS appcast version, channel, HTTPS enclosures, signature encoding, and archive lengths')
