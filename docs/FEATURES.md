# Feature coverage

The target is the public NotchView homepage and release notes, not access to proprietary source. “Implemented” indicates code exists; the verification column says what was actually exercised. No mock quota is shipped as a live integration.

| Planned capability | Implementation | Verification / remaining work |
|---|---|---|
| Notch panel, hover, pin, collapse | AppKit panel, SwiftUI shell, interruptible spring | Launched on a notched M1 Pro MacBook; UI/navigation checked |
| Multi-monitor / no-notch fallback | User-selected persistent display, automatic notch-aware fallback, layout on display changes, top-center fallback | External display/hardware matrix outstanding |
| Full-screen hiding | Bounds-only frontmost-window heuristic | Needs Spaces, Stage Manager and multi-display validation; may treat borderless maximized windows as full-screen |
| Liquid Glass / black appearance | Native glass on 26+, material fallback, solid accessibility mode | Glass UI launched; older OS and accessibility runtime matrix outstanding |
| Claude waiting alerts | Local hooks, minimized payload, independently ordered session states, ended-session tombstones and attention color | Concurrent lifecycle, approval resolution and delayed-event tests pass; live Claude CLI unavailable |
| Claude usage | Official status-line quota bridge, optional previous-command forwarding | Decoder tested; eligible live Claude account/CLI still needed |
| Codex usage | Real app-server query, bucket-aware windows and resets, stale state | Real authenticated quota fetched and displayed |
| Codex approvals | Shared-server status polling and notification handler | Requires a compatible running shared socket; unrelated standalone sessions unsupported |
| Return to agent session | Codex deep link, Terminal tty targeting, application fallback | Routing metadata tested; exact terminal and desktop deep-link behavior needs live session tests |
| File tray | Persistent bookmarks, search, Quick Look, drag-in/out, selection, copy feedback, removal/undo, Finder reveal | Native add/select/remove round trip passed; original file preserved |
| AirDrop | Native sharing service with picker fallback | Requires recipient device for end-to-end delivery |
| Clipboard | Opt-in history, text/images, search, pins, retention, versioned encrypted disk with legacy migration, app exclusions, selection and drag-out | Encryption, tamper detection, exclusions and retention checks pass; no personal history recorded during QA |
| Screenshots | User-selected folder, persistent bookmark, stable completed-file detection, metadata/name filtering | Custom location and localized screenshot names need broader coverage |
| Downloads | New-file tray import; `.crdownload`, `.part` and Safari `.download` package bytes/speed; off-main-thread scans | Package/symlink fixtures pass. Percentage only when usable Safari package metadata supplies a total; universal browser totals remain unavailable |
| Music | Optional system MediaRemote adapter; direct Music/Spotify automation | Private system API can fail on recent macOS; Podcasts, TV, IINA coverage unverified |
| Artwork / compact activity | System metadata artwork, direct Music/Spotify artwork and a compact animated playback symbol | Direct artwork needs live player verification; activity animation is decorative, not audio analysis |
| Volume | Core Audio read/write and notch notice | Actual device level read; keyboard changes and device-switch matrix outstanding |
| Brightness | Optional dynamically loaded DisplayServices adapter | Private compatibility API; external display support unverified |
| Replacing hardware-key HUD | Optional Accessibility-gated system-event tap; handles volume/mute and supported brightness only after a successful device write; other events pass through | Key decoding tests pass. Off by default on every launch; live Accessibility/device testing outstanding. Software controls and unsupported devices retain their system HUD |
| Charging and battery | IOKit power notifications, percentage and OS time estimate | Real charging state/percentage/estimate displayed |
| Per-app power estimates | Optional macOS process-energy deltas, readable app-bundle helper grouping, CPU fallback | Process counters and reset/PID-reuse math tested. Not battery percentage or complete system-energy attribution; OS/hardware support varies |
| AirPods | Optional OS Bluetooth report parser; available component readings | Physical AirPods/OS-version coverage not verified |
| Meetings | Opt-in EventKit read access, restored authorized connection, upcoming list, countdown, recognized HTTPS Join links | Denied-access behavior implemented; real calendar and meeting provider checks outstanding |
| First run / login | Notch tour, welcome notice, ServiceManagement login switch | First-run tour checked; login item not enabled during QA |
| Settings | Native sidebar, grouped forms, contextual setup, support status, display choice, customizable Overview modules and offline privacy/uninstall/licenses | 0.2 UI inspected; 0.3 additions require final live review |
| Global shortcut | Optional Control–Option–Space registration; keyboard-open state and Escape dismissal | No ordinary key-event monitoring or Accessibility requirement; live shortcut check pending |
| Diagnostics | Manual local JSON export using a strict field allowlist | Privacy-schema tests pass; excludes user content, identifiers, paths and process names |
| Sparkle | 2.10 embedded, checks/preferences, stable/beta channels, config validation, release script | Extracted package verified; actual Sparkle archive/feed signature and rejection tests pass. Live notarized upgrade deferred with paid enrollment |

Full parity is not yet achieved. These gaps remain in scope and must not be removed from this matrix to imply completion.

References: [NotchView](https://notchview-site.vercel.app/), [releases](https://github.com/Hrushi2406/notchview-releases/releases), [Claude hooks](https://code.claude.com/docs/en/hooks), [Claude status line](https://code.claude.com/docs/en/statusline), [Codex app server](https://developers.openai.com/codex/app-server/).
