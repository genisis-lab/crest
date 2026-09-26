#!/usr/bin/env python3
import json, os, pathlib, subprocess, sys, tempfile

with tempfile.TemporaryDirectory(prefix='crest-bridge-tests-') as directory:
    root = pathlib.Path(directory)
    env = dict(os.environ, CREST_TEST_DATA_DIR=directory)
    def invoke(mode, payload):
        return subprocess.run([sys.argv[1], mode], input=json.dumps(payload).encode(), env=env, capture_output=True, check=True, timeout=5)
    result = invoke('hook', {'session_id':'fixture-session','hook_event_name':'PermissionRequest','cwd':'/fixture/project','tool_input':{'command':'SECRET_TEST_SENTINEL'},'prompt':'SECRET_TEST_SENTINEL'})
    files = list((root / 'Events').glob('*.json'))
    assert len(files) == 1 and result.stdout == b''
    event = json.loads(files[0].read_text())
    assert event['sessionID'] == 'fixture-session' and event['project'] == 'project'
    assert 'SECRET_TEST_SENTINEL' not in files[0].read_text()
    assert (files[0].stat().st_mode & 0o777) == 0o600
    invoke('statusline', {'session_id':'fixture-session','rate_limits':{'five_hour':{'used_percentage':25,'resets_at':4000000000}}})
    events = [json.loads(p.read_text()) for p in (root / 'Events').glob('*.json')]
    quotas = [e['quota'] for e in events if e.get('quota')]
    assert quotas[0]['windows'][0]['used'] == 25
    (root / 'previous-statusline.json').write_text(json.dumps({'command':"printf 'existing-status'"}))
    forwarded = invoke('statusline', {'session_id':'fixture-session'})
    assert forwarded.stdout == b'existing-status'
    print('PASS bridge payload minimization, private permissions, quota transfer, previous status forwarding')
