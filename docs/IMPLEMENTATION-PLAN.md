# Native Swift notch app: research and implementation plan

Prepared September 25, 2026. This is the original implementation plan. A working development build is now implemented; current coverage, remaining gaps and test evidence are tracked in [FEATURES.md](FEATURES.md) and [VALIDATION.md](VALIDATION.md). The original proposals below are retained for scope comparison.

## Scope and evidence

Build our own macOS utility matching the publicly advertised NotchView capabilities. Use Swift for application and helper code, SwiftUI for views, and AppKit for desktop integration. Proposed minimum deployment target: macOS 14. Start with Apple Silicon MacBooks; test external monitors and Macs without a notch with a top-center fallback.

I inspected the live homepage, its feature presentation and technical FAQs, and the linked release notes for versions 0.5 and 0.6. These describe advertised behavior, not independently tested behavior of the installed application. No purchase, binary installation, or private source access was performed. The linked repository describes itself as builds and an update feed; it does not establish that the app source is available for reuse.

“Cloud” is interpreted as Claude Code because that is what the referenced page names. No cloud-sync product is described. Remote/cloud agent monitoring would be additional scope requiring a supported provider interface. Our utility needs no proprietary backend for its core local functions; authenticated usage refreshes and software updates can still require network access.

Sources: [NotchView homepage and FAQs](https://notchview-site.vercel.app/), [release notes](https://github.com/Hrushi2406/notchview-releases/releases), [release repository](https://github.com/Hrushi2406/notchview-releases).

## Feature inventory and implementation approach

| Capability observed | Our proposed implementation | Verification requirement |
|---|---|---|
| Expanding notch interface | SwiftUI views hosted in an AppKit NSPanel; collapsed, hover-expanded, tray, and temporary alert states | Correct geometry, no accidental focus stealing, keyboard access, multiple displays |
| Music controls | Artwork, title, play/pause, previous/next with separate player adapters | Test Apple Music, Spotify, Podcasts, TV and IINA individually; universal playback access is not assumed |
| Compact now-playing presentation | Artwork and playback animation on either side of notch | Pause animations when idle; distinguish decorative animation from actual audio analysis |
| File tray | Drag files in/out, thumbnails, copy, remove, persistent references | Preserve original files; recover gracefully from moved/deleted files |
| AirDrop | Native macOS sharing interface for one or several selected items | Exercise native share flow and user cancellation |
| Clipboard history | Text, links and images; pinning; drag-out; multi-select copy/delete/AirDrop | Encrypted persistence; retention 1 day–1 year; pins exempt; exclusion settings and password-manager exclusion |
| Screenshot capture into tray | Observe a user-selected screenshot destination and recognize completed screenshot files | Default and custom locations; avoid importing incomplete or unrelated files |
| Download display | Per-source adapters for progress, speed, completion and tray handoff | Folder observation alone cannot guarantee total size or percentage; validate browser coverage |
| Volume overlay | Observe/control supported audio devices via Core Audio and display transient notch UI | Hardware keys, mute, device switching; system-HUD replacement is a separate feasibility gate |
| Brightness overlay | Display adapter and notch UI for supported screens | Built-in screen first; external displays and suppression of Apple HUD need explicit validation |
| Charging animation | Power-source change events and percentage | Plug/unplug, sleep/wake, fully charged and low battery |
| Battery details | Charge state and OS-provided time estimates when available | Never invent missing time estimates; per-app drain attribution requires separate investigation |
| AirPods popup | Connection events and left/right/case battery when available | Physical device testing; individual readings are not assumed to be universally accessible |
| Meetings | Calendar access through EventKit; next meeting, countdown, validated Join URL | Recurring events, time zones, declined/cancelled meetings, permission denial |
| Claude Code alerts | Local event bridge receiving hooks; waiting state, visual alert, session routing | Multiple simultaneous sessions, resolved prompts and exited processes |
| Codex alerts | Versioned adapter for supported events or local session signals | Prove visibility into independently launched CLI/desktop sessions; owning one app-server does not imply global monitoring |
| Claude and Codex usage viewer | Provider cards showing returned window durations, used/remaining percentage and reset time | Real authenticated data, missing buckets, stale/offline state; no inferred quota from token counts |
| Appearance | Black and translucent modes, smooth transitions | Contrast, Reduce Motion and light/dark desktop backgrounds |
| Login greeting | Short welcome animation and configurable launch at login | No repeated greeting on ordinary wake or app relaunch unless configured |
| Full-screen behavior | Hide/suspend presentation in full-screen contexts | Spaces, display changes, menu-bar autohide and screen sharing behavior |
| Settings and first-run tour | Native settings, feature toggles, setup status, notch walkthrough | Explain permissions when enabling the corresponding feature |
| In-app updates | Signed Sparkle update feed and Check for Updates entry | Test upgrade between two signed builds, signature rejection and interrupted downloads |

The homepage is the source for the core inventory; the release notes supply clipboard retention, exclusions, selection/batch operations, settings, onboarding and update details. This table is our implementation proposal, not a description of NotchView internals.

## Architecture

- `AppShell`: lifecycle, settings, menu bar, onboarding and login-item support.
- `NotchUI`: panel placement, hover/hit-testing, animation, layout, accessibility and display management.
- `FeatureCore`: typed events and presentation coordinator. Approval alerts outrank ambient widgets; temporary alerts expire without discarding tray state.
- `AgentIntegrations`: Claude and Codex adapters, session identity, terminal routing and reconnect handling.
- `UsageProviders`: normalized quota snapshots with account/provider identity, bucket IDs, reset dates, source timestamps and freshness.
- `Media`, `Files`, `Clipboard`, `Meetings`, `SystemStatus`: independently enabled services behind protocols.
- `Persistence`: local metadata store, CryptoKit-encrypted clipboard payloads, Keychain-protected encryption key, retention jobs and file bookmarks.
- `UpdateService`: Sparkle integration isolated from the feature engine.

Use Swift concurrency and actors for background work, keeping UI state on the main actor. Prefer OS notifications/file events; use bounded polling only where necessary, such as clipboard change detection. Avoid collecting prompt text for simple agent status. Do not log credentials or clipboard content. Hook setup must merge existing configuration and be reversible.

The panel is grounded in Apple's [NSPanel API](https://developer.apple.com/documentation/appkit/nspanel). Update packaging follows [Sparkle documentation](https://sparkle-project.org/documentation/). These are proposed building blocks, not a claim that every integration has a public API.

## Claude/Codex and usage design

Claude: use `PermissionRequest` and relevant `Notification` hooks to receive local signals, without returning automatic approval decisions. Track session identity and terminal context so clicking an alert can return to the originating session. The [Claude hooks reference](https://code.claude.com/docs/en/hooks) documents these events and differences in when they fire. Prototype a read-only usage source separately; hooks do not establish subscription quota access.

Codex: evaluate `account/rateLimits/read` and `account/rateLimits/updated` through the documented [Codex app-server interface](https://developers.openai.com/codex/app-server/). Preserve provider bucket IDs and durations instead of assuming every plan always has the same five-hour and weekly windows. Approval-event visibility and navigation into an existing unrelated session must be demonstrated separately from querying account limits.

For both: show provider-reported percentages, reset times, plan information only when available, and a visible last-refresh time. Distinguish subscription quota from API spending or local token totals. Missing information displays as unavailable, never as zero. Keep authenticated provider traffic direct; do not route it through our own server.

Exact terminal-tab switching needs terminal-specific support. Start by validating Terminal and iTerm2; show an explicit app-level fallback when exact routing is unavailable. Avoid claiming broad terminal compatibility until tested.

## Ordered delivery plan

1. **Feasibility prototypes.** Validate notch placement, Claude hooks, real Codex quota data, Claude quota access, existing-session detection and terminal routing. In parallel within the work sequence, investigate the system-HUD, player, AirPods, download and battery-attribution interfaces. Output: runnable probes and a feature support matrix with confirmed/conditional/unsupported status. No simulated values counted as working integrations.
2. **Native shell.** Build the Swift project, floating panel, state coordinator, display fallback, settings, launch-at-login and onboarding. Output: installable local app with stable hover and full-screen behavior.
3. **Agent-focused working build.** Deliver Claude/Codex cards, available real usage data, waiting alerts, session switching, reconnect and stale-state handling. This is the first user-testable milestone because these are central to the request.
4. **Files and personal utilities.** Deliver tray, AirDrop, clipboard encryption/retention/exclusions, multi-select, screenshot imports and calendar countdown/Join.
5. **Media and system parity.** Implement validated player adapters, volume/brightness displays, charging/battery, AirPods and download adapters. Record any hardware/OS/provider-specific limitations beside the relevant feature.
6. **Release hardening.** Accessibility, motion/performance tuning, permission-denial paths, migration/recovery, signed/notarized packaging and tested in-app updates.

The entire advertised feature set remains the target; the early milestone is not a substitute for parity. Re-estimate delivery after the first prototypes rather than assigning a misleading schedule to unverified OS/provider capabilities.

## Acceptance criteria and readiness

- Exercise actual integrations on a notched MacBook, including multiple sessions, simultaneous notifications, sleep/wake and full-screen transitions.
- Unit-test quota decoding and reset semantics, event prioritization, session lifecycle, clipboard retention and encryption recovery. Integration-test file operations without deleting original user files.
- Measure idle CPU, memory and energy use; proposed idle CPU target below 1% on the reference Mac, with the machine and workload recorded. Treat this as a target, not a current result.
- Clipboard exclusions must prevent persistence, rather than merely hiding already stored entries. Permission denial must leave unrelated features usable.
- Never mark a feature complete based only on mock data or a preview. Hardware-dependent features require hardware evidence.
- Prefer direct signed/notarized distribution given the breadth of desktop integrations. App Store compatibility must be assessed after API choices are confirmed.

Local check: Swift and Codex executables are present. The selected developer directory is `/Library/Developer/CommandLineTools`; a full Xcode installation and signing identity have not been verified. Neither blocks this plan, but GUI build/release tooling must be checked before implementation and distribution.

Remaining uncertainties: Claude subscription quota source; Codex observation across independently launched sessions; exact terminal routing coverage; all-player metadata/control access; complete system-HUD suppression; AirPods per-component readings; per-app battery attribution; cross-browser download totals. These are explicit prototype gates, not guaranteed capabilities.
