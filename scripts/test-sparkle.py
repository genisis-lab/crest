#!/usr/bin/env python3
"""Exercise Sparkle's actual signature verifier using disposable keys; never touch Keychain."""
import base64
from pathlib import Path
import os
import subprocess
import sys
import tempfile

sign = Path(sys.argv[1])/'sign_update'
def run(arguments, success=True):
    result = subprocess.run([str(sign), *map(str, arguments)], capture_output=True, text=True)
    if (result.returncode == 0) != success:
        raise RuntimeError(f'Sparkle verification expectation failed (exit {result.returncode}): {result.stderr[:500]}')
    return result.stdout.strip()

with tempfile.TemporaryDirectory(prefix='crest-sparkle-test-') as temporary:
    root = Path(temporary)
    key, wrong_key = root/'test-seed', root/'wrong-seed'
    for destination in [key, wrong_key]:
        descriptor = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, 'wb') as output:
            output.write(base64.b64encode(os.urandom(32)))
    archive = root/'fixture.zip'
    archive.write_bytes(b'Crest disposable signature fixture')
    signature = run(['--ed-key-file', key, '-p', archive])
    run(['--verify', '--ed-key-file', key, archive, signature])
    run(['--verify', '--ed-key-file', wrong_key, archive, signature], success=False)
    archive.write_bytes(archive.read_bytes()+b'tampered')
    run(['--verify', '--ed-key-file', key, archive, signature], success=False)
    feed = root/'appcast.xml'
    feed.write_text('<?xml version="1.0"?><rss version="2.0"><channel><title>Crest test</title></channel></rss>')
    run(['--ed-key-file', key, feed])
    run(['--verify', '--ed-key-file', key, feed])
    feed.write_bytes(feed.read_bytes().replace(b'Crest test', b'Crest tampered'))
    run(['--verify', '--ed-key-file', key, feed], success=False)
print('PASS Sparkle archive/feed signing; tampered archive, wrong key, and modified feed rejected')
