# Feature coverage

The target is the public NotchView homepage and release notes, not access to proprietary source. “Implemented” indicates code exists; the verification column says what was actually exercised. No mock quota is shipped as a live integration.

| Planned capability | Implementation | Verification / remaining work |
|---|---|---|
| Notch panel, hover, pin, collapse | AppKit panel, SwiftUI shell, interruptible spring | Launched on a notched M1 Pro MacBook; UI/navigation checked |
| Multi-monitor / no-notch fallback | Notch-aware screen selection, layout on display changes, top-center fallback | External display/hardware matrix outstanding |
| Full-screen hiding | Bounds-only frontmost-window heuristic | Needs Spaces, Stage Manager and multi-display validation; may treat borderless maximized windows as full-screen |
| Liquid Glass / black appearance | Native glass on 26+, material fallback, solid accessibility mode | Glass UI launched; older OS and accessibility runtime matrix outstanding |
| Claude waiting alerts | Local hooks, minimized payload, event states and attention color | Lifecycle model tests pass; live Claude CLI unavailable |
| Claude usage | Official status-line quota bridge, optional previous-command forwarding | Decoder tested; eligible live Claude account/CLI still needed |
| Codex usage | Real app-server query, bucket-aware windows and resets, stale state | Real authenticated quota fetched and displayed |
| Codex approvals | Shared-server status polling and notification handler | Requires a compatible running shared socket; unrelated standalone sessions unsupported |
| Return to agent session | Codex deep link, Terminal tty targeting, application fallback | Routing metadata tested; exact terminal and desktop deep-link behavior needs live session tests |
| File tray | Persistent bookmarks, search, Quick Look, drag-in/out, selection, copy feedback, removal/undo, Finder reveal | Native add/select/remove round trip passed; original file preserved |
| AirDrop | Native sharing service with picker fallback | Requires recipient device for end-to-end delivery |
| Clipboard | Opt-in history, text/images, search, pins, retention, versioned encrypted disk with legacy migration, app exclusions, selection and drag-out | Encryption, tamper detection, exclusions and retention checks pass; no personal history recorded during QA |
| Screenshots | User-selected folder, persistent bookmark, stable completed-file detection, metadata/name filtering | Custom location and localized screenshot names need broader coverage |
| Downloads | New-file tray import; `.crdownload` and `.part` byte growth/speed | Total percentages unavailable; Safari package size/progress not implemented |
| Music | Optional system MediaRemote adapter; direct Music/Spotify automation | Private system API can fail on recent macOS; Podcasts, TV, IINA coverage unverified |
| Artwork / compact activity | System metadata artwork, direct Music/Spotify artwork and a compact animated playback symbol | Direct artwork needs live player verification; activity animation is decorative, not audio analysis |
| Volume | Core Audio read/write and notch notice | Actual device level read; keyboard changes and device-switch matrix outstanding |
| Brightness | Optional dynamically loaded DisplayServices adapter | Private compatibility API; external display support unverified |
| Replacing hardware-key HUD | Optional Accessibility-gated system-event tap; handles volume/mute and supported brightness only after a successful device write; other events pass through | Key decoding tests pass. Off by default on every launch; live Accessibility/device testing outstanding. Software controls and unsupported devices retain their system HUD |
| Charging and battery | IOKit power notifications, percentage and OS time estimate | Real charging state/percentage/estimate displayed |
| Per-app battery drain | Not implemented | No verified reliable adapter yet |
| AirPods | Optional OS Bluetooth report parser; available component readings | Physical AirPods/OS-version coverage not verified |
| Meetings | Opt-in EventKit read access, restored authorized connection, upcoming list, countdown, recognized HTTPS Join links | Denied-access behavior implemented; real calendar and meeting provider checks outstanding |
| First run / login | Notch tour, welcome notice, ServiceManagement login switch | First-run tour checked; login item not enabled during QA |
| Settings | Native sidebar, grouped forms, contextual setup, support status and customizable Overview modules | Opened and inspected |
| Sparkle | 2.10 embedded, checks/preferences, stable/beta channels, config validation, release script | Local signature verified; live signed upgrade needs feed + Developer ID + notary profile + Sparkle key |

Full parity is not yet achieved. These gaps remain in scope and must not be removed from this matrix to imply completion.

References: [NotchView](https://notchview-site.vercel.app/), [releases](https://github.com/Hrushi2406/notchview-releases/releases), [Claude hooks](https://code.claude.com/docs/en/hooks), [Claude status line](https://code.claude.com/docs/en/statusline), [Codex app server](https://developers.openai.com/codex/app-server/).
