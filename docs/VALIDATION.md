# Validation log

Development validation, September 26, 2026. Local environment: Apple M1 Pro, macOS 27, Swift 6.4, using the installed macOS 26.5 SDK to avoid a missing SwiftUI macro plugin in Command Line Tools 27.

## Completed

- Native application compiles with a macOS 14 deployment target. The packaged build contains the Swift bridge and Sparkle framework, passes `codesign --verify --deep --strict`, and is delivered as `dist/Crest.zip`. This is an ad-hoc signed development build, not a notarized distribution release.
- Eleven core checks / 40 assertions cover quota bucket mapping, missing/invalid data, legacy quotas, over-limit values, expired Claude windows, approval lifecycle, session routing identity, clipboard retention/exclusion, authenticated encryption, reversible hook merging and hardware-key filtering. All pass.
- The bridge integration check uses isolated temporary data and verifies minimized payloads, private file permissions, quota transfer, no approval decision output and forwarding an existing status-line command. All pass.
- App launched through the native UI. First-run onboarding, Overview, Agents, Tray, Clipboard, native Settings and Connections were inspected.
- Codex connection was activated through the app. Real quota windows returned and rendered. Account values are intentionally omitted from this repository.
- Actual battery percentage, power connection, time estimate, output volume and supported-display brightness appeared in the UI.
- Final archive was extracted into a clean temporary directory and passed deep signature verification again. The exact packaged app launched, reconnected to Codex automatically, and rendered the native interface.
- Native checkbox selection and removal of a folder reference were also exercised in the final package; the project folder and source files remained intact.
- File tray round trip: selected this project's README through the native Open dialog, verified it appeared, selected it, removed its tray reference, and confirmed the original README still exists. Fixed activation of the Open dialog discovered during this check.
- Clipboard persistence, calendar access, Claude integration installation, login-item enablement, Accessibility permission and AirDrop delivery were not enabled during QA. Permission-dependent integrations therefore remain unverified with live user data/devices.
- The source was pushed to the private `genisis-lab/crest` GitHub repository. The initial GitHub Actions run passed both core tests and packaging; its optional artifact upload failed because the account's artifact-storage quota was full. That optional upload step has been removed. The [follow-up run](https://github.com/genisis-lab/crest/actions/runs/36220172450) for source commit `f5c8fdf` passed all checks and packaging. Local build delivery is unaffected.

## Remaining release gates

- Live Claude hooks/status-line data and multiple concurrent sessions; a compatible shared Codex socket and exact session routing.
- Real calendar authorization/denial, AirDrop recipient delivery, player Automation permissions and physical AirPods/component batteries.
- Accessibility-authorized volume/brightness interception and fallback on unsupported devices. Parser tests do not prove system HUD suppression.
- macOS 14–26 runtime coverage, Intel, external displays, Spaces, Stage Manager, full-screen transitions, sleep/wake and accessibility modes.
- A sustained CPU/memory/energy measurement. One local idle sample was approximately 0% CPU and 83 MB memory, which is not a performance benchmark.
- Developer ID signing/notarization and an end-to-end Sparkle upgrade between two real releases, including rejection and recovery cases in [UPDATES.md](UPDATES.md).

See [FEATURES.md](FEATURES.md) for the explicit parity gaps. Code being present does not mean every integration is verified.


## Version 0.2 UI and reliability pass

- Replaced the tall dashboard with a compact control-center layout and native sidebar Settings. Verified Overview, Agents, Tray, Settings and contextual setup navigation in the running app.
- Keyboard Command-3 navigated to Tray. A disposable text file was added through the native file picker; search showed both the correct match and a no-results state; Quick Look rendered its contents. Remove and Undo removal visibly updated the tray. The test reference was then removed and the original file remained intact.
- Found and repaired a launch hang when clipboard restoration waited for Keychain access on the main thread. The subsequent packaged app launched successfully without a Keychain prompt; unavailable access left recording off and retained the encrypted archive.
- Thirteen core checks / 47 assertions passed, including legacy clipboard archive migration, unsupported archive rejection, and time-based quota freshness. Bridge integration passed. Eight invalid release configurations were rejected without changing the target bundle; valid release metadata was accepted.
- Pinning intentionally starts off each launch. Exit grace reduced from 650 to 120 ms; animation uses the common run-loop mode and a faster critically damped spring. Runtime response still includes animation and system scheduling; 120 ms is the configured grace, not a measured total collapse time.
- Synced Documents caused compiler intermediates to change during a build. Build/test/release scripts now share a per-project cache and content-identical source snapshot outside File Provider storage.
- Final visual review found and corrected a blank Settings window opened by Command-comma and a clipped section heading. The shortcut now opens the same Settings window as the app controls. The final 0.2.0 build visibly shows the General heading and Keep the notch expanded switched off.
- The final production-configuration development archive (version 0.2.0, build 2) was extracted into a fresh temporary directory and passed deep, strict signature verification. Its compiled source snapshot was byte-compared with the repository source and matched. Signing remains ad hoc.

The release gates above remain open. This pass does not establish production readiness, universal hardware support, or a completed signed Sparkle upgrade.
