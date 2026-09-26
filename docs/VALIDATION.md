# Validation log

Initial implementation, September 2026. Local environment: Apple M1 Pro, macOS 27, Swift 6.4, using the installed macOS 26.5 SDK to avoid a missing SwiftUI macro plugin in Command Line Tools 27.

- Native application compiles with a macOS 14 deployment target.
- Ten core checks / 34 assertions cover quota bucket mapping, missing/invalid data, legacy quotas, over-limit values, expired Claude windows, approval lifecycle, session routing identity, clipboard retention/exclusion, authenticated encryption and reversible hook merging. All pass after repairing a numeric duration conversion caught by the checks.
- App launched through the native UI. First-run onboarding, Overview, Settings and Connections were inspected.
- Codex connection was activated through the app. Real five-hour and weekly quota windows returned and rendered. Account values are intentionally omitted from this repository.
- Actual battery percentage, charging state, time estimate and output volume appeared in the UI.
- No personal clipboard recording, calendar permission, Claude config mutation, login-item enablement or AirDrop transmission was performed during these checks.

Pending: release-build packaging verification, source push, physical-device integrations and live signed update test. This file is updated as those checks complete.
