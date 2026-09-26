# Validation log

Development validation, September 26, 2026. Local environment: Apple M1 Pro, macOS 27, Swift 6.4, using the installed macOS 26.5 SDK to avoid a missing SwiftUI macro plugin in Command Line Tools 27.

## Completed

- Native application compiles with a macOS 14 deployment target. The packaged build contains the Swift bridge and Sparkle framework, passes `codesign --verify --deep --strict`, and is delivered as `dist/Crest.zip`. This is an ad-hoc signed development build, not a notarized distribution release.
- Eleven core checks / 40 assertions cover quota bucket mapping, missing/invalid data, legacy quotas, over-limit values, expired Claude windows, approval lifecycle, session routing identity, clipboard retention/exclusion, authenticated encryption, reversible hook merging and hardware-key filtering. All pass.
- The bridge integration check uses isolated temporary data and verifies minimized payloads, private file permissions, quota transfer, no approval decision output and forwarding an existing status-line command. All pass.
- App launched through the native UI. First-run onboarding, Overview, Agents, Tray, Clipboard, native Settings and Connections were inspected.
- Codex connection was activated through the app. Real quota windows returned and rendered. Account values are intentionally omitted from this repository.
- Actual battery percentage, power connection, time estimate, output volume and supported-display brightness appeared in the UI.
- File tray round trip: selected this project's README through the native Open dialog, verified it appeared, selected it, removed its tray reference, and confirmed the original README still exists. Fixed activation of the Open dialog discovered during this check.
- Clipboard persistence, calendar access, Claude integration installation, login-item enablement, Accessibility permission and AirDrop delivery were not enabled during QA. Permission-dependent integrations therefore remain unverified with live user data/devices.
- The source was pushed to the private `genisis-lab/crest` GitHub repository. The initial GitHub Actions run passed both core tests and packaging; its optional artifact upload failed because the account's artifact-storage quota was full. That optional upload step has been removed. Local build delivery is unaffected.

## Remaining release gates

- Live Claude hooks/status-line data and multiple concurrent sessions; a compatible shared Codex socket and exact session routing.
- Real calendar authorization/denial, AirDrop recipient delivery, player Automation permissions and physical AirPods/component batteries.
- Accessibility-authorized volume/brightness interception and fallback on unsupported devices. Parser tests do not prove system HUD suppression.
- macOS 14–26 runtime coverage, Intel, external displays, Spaces, Stage Manager, full-screen transitions, sleep/wake and accessibility modes.
- A sustained CPU/memory/energy measurement. One local idle sample was approximately 0% CPU and 83 MB memory, which is not a performance benchmark.
- Developer ID signing/notarization and an end-to-end Sparkle upgrade between two real releases, including rejection and recovery cases in [UPDATES.md](UPDATES.md).

See [FEATURES.md](FEATURES.md) for the explicit parity gaps. Code being present does not mean every integration is verified.
