# Crest: path to a production release

Review date: September 26, 2026. Target: a native macOS utility inspired by the interaction patterns of [NotchView](https://notchview-site.vercel.app/), with an original interface. Source remains private. Version 0.2 is a development build, not a production release.

## What changed in 0.2

- Compact Overview with Now Playing, sound/display controls, battery and provider usage. Removed oversized branding and marketing copy from the working interface.
- Stable dark content surfaces, restrained system typography, SF Symbols, native controls and a Liquid Glass outer edge on supported macOS versions. Reduced motion/transparency and increased contrast remain supported in code.
- Native sidebar Settings, contextual setup links, and controls for which Overview modules are visible. Pinning starts off at every launch. Pointer-exit grace is 120 ms (previously 650 ms), followed by a faster interruptible spring; file dialogs, dragging and Quick Look suspend collapse.
- File search, Quick Look, undo for tray removal, selection maintenance and copy feedback. Removal continues to affect references only.
- Pinned clipboard entries appear first. Empty searches have their own state; hidden selections are cleared when the search changes.
- Agent attention remains visible while the request is outstanding. Usage age updates over time, reset labels include dates, disconnected data is labeled, and refresh requests have timeouts.
- Reconnection discards replies from older subprocesses. Startup no longer performs a blocking clipboard Keychain operation on the main thread. Only an explicit recording action may request authentication.
- Clipboard storage has a versioned envelope and reads the original 0.1 format. Unknown newer formats fail without rewriting history. Unreadable tray metadata is preserved; malformed metadata is backed up before a replacement is written.
- Compilation uses a content-identical source snapshot and outputs in the local user cache rather than the synced source folder, avoiding File Provider timestamp mutations during builds.
- Release configuration rejects unsafe version strings and unsuitable feed/download URLs before notarization. Regression checks ensure invalid configuration does not alter the bundle.

## Ship a defined 1.0, then extend compatibility

Production readiness and total feature parity are different goals. A stable 1.0 can ship with an explicit supported-device and feature list. Features that cannot be validated should stay off by default, remain clearly experimental, or be omitted from release claims. Do not claim universal media support, global Codex-session monitoring, browser download percentages, or per-app battery attribution.

Recommended first support scope: Apple Silicon Macs on a macOS version actually tested end to end. The current deployment target is macOS 14, but compilation alone does not justify advertising runtime support on every release from 14 onward.

## Release blockers

| Priority | Work | Completion evidence |
|---|---|---|
| P0 | Developer ID Application signing and Apple notarization | A clean Mac opens the downloaded, quarantined app without bypassing Gatekeeper; nested Sparkle/helper signatures verify; notarization ticket is stapled |
| P0 | Stable bundle identity and Keychain access | Choose the long-term bundle identifier/signing team before distribution; clipboard works across a real signed upgrade without regenerating or losing its encryption key |
| P0 | Real Sparkle distribution | Choose an HTTPS feed/download host, create and back up the Ed25519 signing key, publish a signed test feed, and upgrade an older notarized build to the next one |
| P0 | Update failure and channel tests | Reject tampered archives; recover from interrupted/offline downloads; stable builds exclude beta releases; cancelling leaves the old app usable |
| P0 | Privacy and recovery validation | Permission denial/revocation, locked Keychain, unavailable key, corrupted archive, disk full, and restart do not freeze the app or overwrite existing data; verify clipboard exclusions and retention on a signed build |
| P0 | Critical user journeys | Add/search/preview/copy/AirDrop/remove/undo files; encrypted clipboard pins/copy/delete; multiple Claude sessions; live usage expiry; supported terminal routing; reconnect after sleep |
| P1 | Supported Mac/OS matrix | Notch/no notch, external display, Spaces/full screen, display changes, sleep/wake, screen sharing, Reduce Motion, Reduce Transparency, Increase Contrast, VoiceOver and keyboard-only navigation |
| P1 | Sustained resource measurements | Record idle CPU, memory and wakeups over at least 30 minutes, then repeat with media, clipboard and folder watchers enabled; inspect growth over a day and during repeated reconnects |
| P1 | Packaging and user support | Installer/archive and checksums, release notes, privacy statement, documented uninstall/integration removal, support contact and a reproducible problem-report template |
| P1 | Release review | Audit permissions, private-API isolation, subprocess handling, retained data, dependency versions and license notices; run CI on the exact release commit |

A source repository can remain private while binaries and the Sparkle feed use a separate download location. Private GitHub release assets are not an anonymous update host. An authenticated delivery design is possible, but requires its own implementation and testing. Never embed a GitHub token in the application.

## Compatibility work after the release gates

- Verify real Claude hooks and status-line quota against the installed provider version. Test multiple terminal sessions and approval resolution.
- Expand Codex session visibility only through a validated provider interface. The current standalone app-server connection retrieves usage; shared-server monitoring requires the corresponding socket.
- Validate Music and Spotify first. Treat system MediaRemote, DisplayServices and hardware-key interception as compatibility adapters, with fallback when unavailable.
- Test physical AirPods models and OS-reported component batteries. Do not synthesize missing readings.
- Folder-based downloads expose bytes and speed, not reliable universal totals. Add a browser-specific adapter only where a supported source can provide completion/total size.
- Per-app battery drain remains unimplemented. Investigate a reliable, permission-appropriate measurement source before presenting attribution to users.

## Useful next additions

After the blockers: user-selected display placement, an optional keyboard shortcut to open Crest from any app, and an opt-in diagnostics export that excludes clipboard/calendar content, prompts and credentials. Favor these reliability and accessibility improvements over adding more widgets before 1.0.

## External inputs still needed

Developer ID identity/signing team, an existing notarization profile, a chosen update host/domain, and a securely generated Sparkle signing key. Hardware and provider accounts are needed for the remaining integration matrix. No public release, new public repository, or hosted endpoint has been created by this UI work.

References: [Apple materials](https://developer.apple.com/design/human-interface-guidelines/materials), [Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution), [Sparkle setup and distribution](https://sparkle-project.org/documentation/). Current coverage: [FEATURES.md](FEATURES.md). Test evidence: [VALIDATION.md](VALIDATION.md).
