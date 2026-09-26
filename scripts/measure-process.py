#!/usr/bin/env python3
"""Measure one local process without collecting arguments, titles, or user content."""
import argparse
import ctypes
import json
from pathlib import Path
import statistics
import time

class Usage(ctypes.Structure):
    _fields_ = [('uuid', ctypes.c_uint8 * 16)] + [(name, ctypes.c_uint64) for name in (
        'user_ns', 'system_ns', 'package_wakeups', 'interrupt_wakeups', 'pageins',
        'wired_bytes', 'resident_bytes', 'footprint_bytes', 'start', 'exit')]

parser = argparse.ArgumentParser()
parser.add_argument('--pid', type=int, required=True)
parser.add_argument('--duration', type=float, default=1800)
parser.add_argument('--interval', type=float, default=15)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
if args.duration <= 0 or args.interval <= 0:
    parser.error('duration and interval must be positive')
library = ctypes.CDLL('/usr/lib/libproc.dylib', use_errno=True)
library.proc_pid_rusage.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_void_p]
library.proc_pid_rusage.restype = ctypes.c_int
samples = []
started = time.monotonic()
previous = None
reason = 'duration completed'
while True:
    usage = Usage()
    if library.proc_pid_rusage(args.pid, 0, ctypes.byref(usage)) != 0:
        reason = 'process unavailable'
        break
    now = time.monotonic()
    if previous is not None:
        old, timestamp = previous
        if old.start != usage.start:
            reason = 'process restarted'
            break
        elapsed = now - timestamp
        samples.append(dict(elapsed_seconds=round(now-started, 3),
            cpu_percent=round(max(0, usage.user_ns+usage.system_ns-old.user_ns-old.system_ns)/elapsed/1e7, 3),
            footprint_mb=round(usage.footprint_bytes/1e6, 3),
            interrupt_wakeups_per_second=round(max(0, usage.interrupt_wakeups-old.interrupt_wakeups)/elapsed, 3),
            package_wakeups_per_second=round(max(0, usage.package_wakeups-old.package_wakeups)/elapsed, 3)))
    previous = usage, now
    if now-started >= args.duration:
        break
    time.sleep(min(args.interval, args.duration-(now-started)))
report = dict(schema_version=1, requested_seconds=args.duration, measured_seconds=round(time.monotonic()-started, 3),
    outcome=reason, scope='Selected process only; no child processes. Activity during collection is not controlled.', samples=samples)
if samples:
    report['summary'] = dict(mean_cpu_percent=round(statistics.mean(s['cpu_percent'] for s in samples), 3),
        max_cpu_percent=max(s['cpu_percent'] for s in samples),
        first_footprint_mb=samples[0]['footprint_mb'], last_footprint_mb=samples[-1]['footprint_mb'],
        max_footprint_mb=max(s['footprint_mb'] for s in samples),
        mean_interrupt_wakeups_per_second=round(statistics.mean(s['interrupt_wakeups_per_second'] for s in samples), 3))
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(report, indent=2)+'\n')
print(json.dumps({key:value for key,value in report.items() if key != 'samples'}, indent=2))
