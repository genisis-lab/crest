# Crest

A native Swift notch companion for macOS 14 and later. Built with SwiftUI, AppKit and Sparkle 2.10. Liquid Glass is used on macOS 26+, with material and accessibility fallbacks.

**Status: working development build, not full verified NotchView parity.** The project is an original implementation based on the advertised feature list. It does not contain NotchView source or assets.

## Build and run

Requires macOS, Swift 5.10+ tooling, a macOS 26+ SDK for compiling the Liquid Glass branch, and network access to resolve the pinned Sparkle package. Deployment minimum is macOS 14. Apple Silicon is the locally tested architecture.

```sh
bash scripts/test.sh
bash scripts/build.sh
open "$(cat dist/app-path.txt)"
```

The build script creates an ad-hoc signed local application in a temporary staging directory and delivers `dist/Crest.zip`. Unzip it into Applications for persistent use. Staging outside synced Documents avoids File Provider metadata interfering with code signing. It does not install a login item, publish a release, or grant permissions. You can also open `Package.swift` in Xcode. The packaging script embeds Sparkle and the Swift bridge helper into an application bundle.

On some Command Line Tools 27 installations, the SwiftUI macro plugin is absent. The scripts prefer the installed macOS 26.5 SDK in that case. Override `CREST_SDK`, `CREST_BUILD_DIR`, `CREST_DIST_DIR` or `CREST_CONFIGURATION` as needed. The assertion runner has no XCTest/Swift Testing dependency, so it runs with Command Line Tools alone.

## Using Crest

Hover the notch to expand it. Pin it to stay open, or use the menu-bar mountain icon. Macs without a notch use a top-center panel. Drag files into the panel, select them, then copy, AirDrop or remove the tray reference. Removing a tray item never deletes the source file.

The interface contains Overview, Agents, Tray and Clipboard. Native Settings includes General, Connections, Files & Privacy, Media & System, and Updates.

### Claude and Codex

- **Codex usage:** in Connections, select the installed Codex executable and connect. Crest uses `account/rateLimits/read` through Codex app-server and your existing Codex login. It does not extract tokens or store a second credential copy. Real quota retrieval was verified locally.
- **Codex session monitoring:** optionally supply a running shared app-server's Unix socket. Crest polls thread status without starting or resuming turns. Unrelated desktop/CLI sessions are not visible through a new standalone app-server. Shared-server monitoring is implemented but not verified against a live shared server in this environment.
- **Claude:** install the bridge from Connections. It merges hooks into `~/.claude/settings.json`, saves a local backup, and can wrap an existing status-line command. Restart Claude sessions after installation. Remove Integration removes only Crest's hooks and restores the prior status line when applicable.
- **Claude usage:** uses official status-line `rate_limits` fields, requiring Claude Code 2.1.251+ and an eligible provider account. It does not read subscription credentials. Claude Code is not installed in the development environment, so live Claude testing remains outstanding.
- **Approvals:** Crest only displays state and routes back to the session; it never approves an action. Terminal tty routing is implemented; other terminals currently fall back to opening the app. Codex routing uses its thread URL.

### Privacy and permissions

Clipboard recording, calendar access, media automation, Bluetooth monitoring and folder watching start off. Enable each in Settings when needed. Clipboard history is AES-GCM encrypted; its random key is held in the macOS Keychain. Known password managers, concealed clipboard types, unknown source apps and configured exclusions are filtered before persistence. This is not a universal secret detector; text copied from ordinary apps can still contain secrets.

Calendar connections and selected watched folders are restored after restart only after opt-in. Experimental hardware-key HUD replacement requires Accessibility permission and explicit enablement each launch; unsupported controls keep the system overlay.

Local application data is stored in `~/Library/Application Support/Crest`, outside this repository. File-tray metadata uses local bookmarks. Temporary agent events contain provider/session identity, project basename, terminal-routing fields and quota snapshots, not prompts or tool arguments. No Crest analytics or proprietary backend is included. Codex's own configuration still governs its subprocess behavior.

## Coverage and limitations

See [FEATURES.md](docs/FEATURES.md) for the implementation/verification matrix and [VALIDATION.md](docs/VALIDATION.md) for test evidence. Features that depend on private compatibility APIs, hardware, permissions or external provider versions are not represented as universally supported.

## Updates

Sparkle is linked, embedded and connected to menu/Settings controls. A local build deliberately has no update feed or signing key. See [UPDATES.md](docs/UPDATES.md) for the release procedure.

A private source repository is compatible with Sparkle, but private GitHub release URLs are not anonymously downloadable. Use a separate public binary-only update location, or implement authenticated distribution before shipping. Never embed a GitHub personal token in the application.

## Design

The UI applies the user-selected [Apple Design skill](https://github.com/emilkowalski/skills/blob/main/skills/apple-design/SKILL.md): native typography and controls, an interruptible critically damped panel, material hierarchy and accessibility preferences. Apple's native `glassEffect` is used rather than an imitation. Data cards remain dark and stable for readability. Settings follows the system appearance.

## Project layout

`Sources/Crest` contains app services and UI. `Sources/CrestCore` contains testable quota/event/privacy models. `Sources/CrestBridge` is the local Claude helper. `Tests/CrestCoreTests` is the dependency-free assertion suite. `scripts` contains local packaging and release preparation. `Resources` contains app metadata and the original programmatically drawn icon.

Sparkle is distributed under its upstream license. The original Crest source is private; no public open-source license has been selected.
