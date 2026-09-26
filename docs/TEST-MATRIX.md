# Release validation matrix

This separates repeatable local evidence from tests needing another account, device or distribution identity. Passing the automated suite is not a substitute for the remaining live checks.

| Area | Evidence available | Remaining scenario |
|---|---|---|
| Core logic | Quotas, independent sessions, delayed events, retention, exclusions, archive migration and tamper checks | Real provider changes and longer multi-session use |
| Clipboard recovery | Missing key, wrong key, corrupt archive and unreadable-path tests preserve the existing bytes; only a genuinely absent archive permits key creation | Locked Keychain and real signed upgrade continuity; disk-full stress; user-granted recording tests |
| File tray | Native add/search/preview/remove/Undo round trip in 0.2; original file retained | AirDrop to a receiving device; unavailable/moved/remounted files |
| Downloads | Safari package fixtures with metadata, payload and symlinks; partial files and unknown/invalid totals | Current real Safari/Chrome/Firefox downloads, pause/resume and interrupted transfers |
| App power | Live process-counter access, nanosecond/nanojoule delta tests, reset/PID-reuse/sleep-interval handling | Hardware/OS comparison, helper attribution beyond app bundles and profiler comparison |
| Diagnostics | Strict JSON-key and feature-name allowlist tests | Manual export dialog and offline-help visual inspection |
| Updates | Real Sparkle signature verification rejects modified archives, wrong keys and modified feeds; metadata/channel tests | Actual old-to-new notarized installation; offline/interruption/cancel/rollback |
| Package | Archive extraction, deep strict signature verification, identity/version/helper/framework/resources/architecture checks and SHA-256 manifest | Quarantined download on a separate clean Mac with Developer ID and a stapled ticket |
| macOS | Local notched Apple Silicon Mac, macOS 27 with macOS 14 deployment minimum | macOS 14–26 runtime checks, Intel if support is intended |
| Displays | Notch-aware current display and preferred-display fallback code | Physical disconnect/reconnect, multiple scaling modes and no-notch Mac |
| Window behavior | Pointer exit, pin-off launch, keyboard navigation and settings inspected in 0.2 | Spaces, Stage Manager, full-screen and screen-sharing matrix |
| Accessibility | Reduce Motion/Transparency/Increase Contrast code paths | VoiceOver, keyboard-only traversal, runtime preference changes |
| Providers | Live Codex quota retrieved in 0.2; current executable located | Claude CLI/account unavailable; no managed shared Codex socket currently running |
| Permissions/hardware | Permission-gated integrations stay opt-in | Calendar denial/revocation, Music/Spotify Automation, Accessibility tap and physical AirPods |
| Performance | Reproducible local `measure-process.py` records only CPU, footprint and wakeup counts | Repeat 30 minutes with each opt-in integration and a day-long stress run |

## Resource sampling

Run against the exact app PID, with a known configuration and no concurrent benchmark workload:

```sh
python3 scripts/measure-process.py --pid APP_PID --duration 1800 --interval 15 --output /tmp/crest-resources.json
```

The output records no command lines, window titles or user content. CPU uses macOS cumulative process CPU nanoseconds; one saturated core is 100%. Footprint is decimal MB. Wakeup counters are process-level kernel values. Child processes are excluded. Record enabled features, whether the panel was open, and other active workload alongside each report. A short or interrupted capture must be labeled as such.

## Future distribution rehearsal

Keep public distribution deferred until the owner elects paid enrollment. Then choose stable bundle/team/key identities; generate and back up an app-specific Sparkle key; sign/notarize two versions; host the feed and archives on the chosen HTTPS location; verify upgrades preserve Keychain access and data. Exercise failure cases before publishing the first production claim.
