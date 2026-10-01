# Crest

A native Swift notch companion for macOS 14 and later. Built with SwiftUI, AppKit and Sparkle 2.10. Liquid Glass is used on macOS 26+, with material and accessibility fallbacks.

**Status: 0.4.0 development build, not full verified NotchView parity.** The project is an original implementation based on the advertised feature list. It does not contain NotchView source or assets.

## Install

On a Mac with the Swift toolchain (Xcode or Command Line Tools), from a clone of this repository:

```sh
bash scripts/install.sh
```

It builds, verifies and copies `Crest.app` into `/Applications` (or `~/Applications` when `/Applications` is not writable), replacing an older Crest, then opens it. Without a toolchain, download the `Crest-<commit>` artifact from a successful [Actions run](https://github.com/genisis-lab/crest/actions) and pass it to the same script; it accepts the downloaded zip, the unzipped folder, `Crest.zip` or `Crest.app`:

```sh
bash scripts/install.sh ~/Downloads/Crest-<commit>.zip
```

The script checks the archive checksum and signature, only ever replaces an app with Crest's bundle identifier, and clears the download quarantine flag so the ad-hoc signed development build can open. Application Support data and Keychain entries are kept across reinstalls. Because each local build has a new ad-hoc signature, macOS may ask again for Keychain, Automation or Accessibility access.

## Build and run

Requires macOS, Swift 5.10+ tooling, a macOS 26+ SDK for compiling the Liquid Glass branch, and network access to resolve the pinned Sparkle package. Deployment minimum is macOS 14. Apple Silicon is the locally tested architecture.

```sh
bash scripts/test.sh
bash scripts/build.sh
open "$(cat dist/app-path.txt)"
```

The build script creates an ad-hoc signed local application in a temporary staging directory and delivers `dist/Crest.zip`. Unzip it into Applications for persistent use. A content-identical source snapshot and compiler intermediates use a per-project directory under `~/Library/Caches/Crest`; app staging uses the system temporary directory. Keeping both outside synced Documents avoids File Provider changes interfering with compilation and code signing. It does not install a login item, publish a release, or grant permissions. You can also open `Package.swift` in Xcode. The packaging script embeds Sparkle and the Swift bridge helper into an application bundle. It extracts and checks the archive, then writes `dist/Crest.manifest.json` and `dist/Crest.sha256`.

On some Command Line Tools 27 installations, the SwiftUI macro plugin is absent. The scripts prefer the installed macOS 26.5 SDK in that case. Override `CREST_SDK`, `CREST_BUILD_DIR`, `CREST_DIST_DIR` or `CREST_CONFIGURATION` as needed. The assertion runner has no XCTest/Swift Testing dependency, so it runs with Command Line Tools alone.

## Using Crest

Hover the notch to expand it (after a short pause by default; choose instant, a longer pause or click-only in General settings). It begins collapsing 120 ms after the pointer leaves, except while using a file dialog, dragging, previewing or typing a note. Pin it to stay open, or use the menu-bar mountain icon. Pinning is off at each launch and is never restored automatically. Macs without a notch use a top-center panel. Drag files into the panel, select them, then copy, AirDrop or remove the tray reference. Removing a tray item never deletes the source file.

The interface contains Overview, Agents, Tray, Clipboard and Notes. Overview modules can be hidden in Settings. Native sidebar Settings includes General, Connections, Files & Privacy, Media & System, Updates and Support. Command-1 through Command-5 switch sections while Crest is focused; Command-P pins it and Escape collapses it. File search, Quick Look, and undo for tray removal are built in. General settings also supports a preferred display and an optional Control–Option–Space global shortcut. Keyboard-opened panels close with Escape or loss of focus. The shortcut does not observe ordinary typing.

### Live activities, focus and notes

While closed, the notch shows the most important current activity beside the cutout: an agent waiting for you, a running focus timer, a meeting starting within ten minutes, or an active download. Otherwise it shows Now Playing artwork or the battery level. Volume and brightness changes show a level bar. Live activities can be turned off in General settings.

- **Focus timer:** start 5–45 minute timers from Overview or 5–60 minutes from the menu-bar icon. Pause, resume, add five minutes or stop. A running timer survives relaunch and plays a sound when it ends (optional).
- **Keep Mac Awake:** the cup button in the battery card or the menu-bar submenu holds a macOS display-sleep assertion indefinitely or for 30 minutes to 2 hours. It ends when Crest quits.
- **Notes:** a scratchpad saved automatically to `notes.txt` in Application Support with owner-only permissions. Notes are not encrypted.
- **Now Playing** shows elapsed and remaining time. Drag the bar to seek when the player supports it.
- **Tray** rows show Quick Look thumbnails, size and folder; double-click opens a file. **Clipboard** rows copy on click, and can be filtered to pinned items, links or images; links can be opened and hex colors show a swatch.

### Claude and Codex

- **Codex usage:** in Connections, select the installed Codex executable and connect. Crest uses `account/rateLimits/read` through Codex app-server and your existing Codex login. It does not extract tokens or store a second credential copy. Real quota retrieval was verified locally.
- **Codex session monitoring:** optionally supply a running shared app-server's Unix socket. Crest polls thread status without starting or resuming turns. Unrelated desktop/CLI sessions are not visible through a new standalone app-server. Shared-server monitoring is implemented but not verified against a live shared server in this environment.
- **Claude:** install the bridge from Connections. It merges hooks into `~/.claude/settings.json`, saves a local backup, and can wrap an existing status-line command. Restart Claude sessions after installation. Remove Integration removes only Crest's hooks and restores the prior status line when applicable.
- **Claude usage:** uses official status-line `rate_limits` fields, requiring Claude Code 2.1.251+ and an eligible provider account. It does not read subscription credentials. Claude Code is not installed in the development environment, so live Claude testing remains outstanding.
- **Approvals:** Crest only displays state and routes back to the session; it never approves an action. Terminal tty routing is implemented; other terminals currently fall back to opening the app. Codex routing uses its thread URL.

### Downloads and app power

Folder monitoring supports Safari `.download` packages and Chrome/Firefox partial files. It shows payload size and growth speed; a percentage appears only if package metadata supplies a usable total. Scanning runs outside the UI thread and does not follow symlinks or inspect browser history.

Media & System includes optional app power estimates. It reads macOS process-energy counters and groups readable helpers inside each running app bundle. Values are process power estimates, not battery percentages or complete system power; unsupported energy counters fall back to CPU activity. Names and samples stay in memory.

### Privacy and permissions

Clipboard recording, calendar access, media automation, Bluetooth monitoring and folder watching start off. Enable each in Settings when needed. Clipboard history is AES-GCM encrypted; its random key is held in the macOS Keychain. Known password managers, concealed clipboard types, unknown source apps and configured exclusions are filtered before persistence. This is not a universal secret detector; text copied from ordinary apps can still contain secrets.

Calendar connections and selected watched folders are restored after restart only after opt-in. Experimental hardware-key HUD replacement requires Accessibility permission and explicit enablement each launch; unsupported controls keep the system overlay.

Local application data is stored in `~/Library/Application Support/Crest`, outside this repository. File-tray metadata uses local bookmarks. Temporary agent events contain provider/session identity, project basename, terminal-routing fields and quota snapshots, not prompts or tool arguments. Support includes a manual, local diagnostics export with a strict allowlist and bundled privacy, uninstall and license documents. No Crest analytics or proprietary backend is included. Codex's own configuration still governs its subprocess behavior.

## Coverage and limitations

See [PRODUCTION-READINESS.md](docs/PRODUCTION-READINESS.md) for the prioritized release gates and [FEATURES.md](docs/FEATURES.md) for the implementation/verification matrix and [VALIDATION.md](docs/VALIDATION.md) for test evidence. Features that depend on private compatibility APIs, hardware, permissions or external provider versions are not represented as universally supported.

## Updates

Paid Apple Developer enrollment and public distribution are deferred by the owner. Sparkle is linked, embedded and connected to menu/Settings controls. A local build deliberately has no update feed or signing key. See [UPDATES.md](docs/UPDATES.md) for the future release procedure. Actual Sparkle archive/feed signing and tamper rejection are tested locally with disposable keys; this is not a completed updater installation test.

A private source repository is compatible with Sparkle, but private GitHub release URLs are not anonymously downloadable. Use a separate public binary-only update location, or implement authenticated distribution before shipping. Never embed a GitHub personal token in the application.

## Design

The UI applies the user-selected [Apple Design skill](https://github.com/emilkowalski/skills/blob/main/skills/apple-design/SKILL.md): native typography and controls, an interruptible critically damped panel, material hierarchy and accessibility preferences. Apple's native `glassEffect` is used rather than an imitation. Data cards remain dark and stable for readability. Settings follows the system appearance.

## Project layout

`Sources/Crest` contains app services and UI. `Sources/CrestCore` contains testable quota/event/privacy models. `Sources/CrestBridge` is the local Claude helper. `Tests/CrestCoreTests` is the dependency-free assertion suite. `scripts` contains local packaging and release preparation. `Resources` contains app metadata and the original programmatically drawn icon.

Sparkle is distributed under its upstream license. The original Crest source is private; no public open-source license has been selected.
