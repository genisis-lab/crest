#!/usr/bin/env python3
"""Inject validated public release settings. Never handles signing private keys."""
import base64, json, plistlib, re, sys
from urllib.parse import urlparse
config = json.load(open(sys.argv[1]))
url = urlparse(config['feed_url'])
if url.scheme != 'https' or not url.hostname or url.username or url.password:
    raise SystemExit('feed_url must be a public HTTPS URL without credentials')
key = base64.b64decode(config['sparkle_public_key'], validate=True)
if len(key) != 32:
    raise SystemExit('Sparkle Ed25519 public key must decode to 32 bytes')
if not re.fullmatch(r'[1-9][0-9]*', str(config['build'])):
    raise SystemExit('build must be a positive, monotonically increasing integer')
with open(sys.argv[2], 'rb') as f:
    plist = plistlib.load(f)
plist.update(SUFeedURL=config['feed_url'], SUPublicEDKey=config['sparkle_public_key'],
             CFBundleVersion=str(config['build']), CFBundleShortVersionString=config['version'],
             SUEnableAutomaticChecks=True)
with open(sys.argv[2], 'wb') as f:
    plistlib.dump(plist, f)
