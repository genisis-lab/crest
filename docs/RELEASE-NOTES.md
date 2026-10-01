# Crest 0.4.0 — development build

- Live activities in the collapsed notch: an agent waiting for you, a running focus timer, a meeting starting within ten minutes and active downloads, each with a compact indicator. Volume and brightness changes show a HUD level bar instead of text.
- Focus timer with presets, pause/resume, +5 minutes and an optional completion sound. Available from Overview and the menu-bar icon; a running timer survives relaunch and sleep.
- Keep Mac Awake from the battery card or menu bar, indefinitely or for a fixed time.
- New Notes tab: an automatically saved plain-text scratchpad. The panel stays open while you type and collapses after you click elsewhere.
- Now Playing shows elapsed/remaining time with drag-to-seek for the system adapter, Music and Spotify.
- Tabs moved into the header with an animated selection and badges for waiting agents and tray items. Expanded content fades in; reduced motion is respected.
- Tray: Quick Look thumbnails, file size and folder, open/reveal actions, double-click to open and Clear with Undo.
- Clipboard: click a row to copy it, filters for pinned items, links and images, open-link action, color swatches for hex values and per-row pin/delete on hover.
- Agents: waiting sessions are highlighted and show how long ago they changed. Optional sound when an agent needs you.
- Settings: hover-to-open delay (default is a short pause), haptic feedback, live activities and battery-percentage toggles, sounds and a Focus module toggle.
- Audio and brightness polling now publish only actual changes, reducing panel redraws.
- `scripts/install.sh` installs a local build or a downloaded CI artifact into Applications. CI exercises it and uploads the packaged archive when storage quota allows.

Previous release:

## Crest 0.3.0 — development build

- Choose the display where Crest appears. A disconnected display falls back automatically and is remembered for reconnection.
- Optional Control–Option–Space shortcut, registered with macOS without reading ordinary keyboard input. Keyboard-opened panels stay usable until Escape, losing focus, or pointer interaction.
- Optional app power estimates from macOS process counters, including readable helpers within the app bundle. Unsupported energy counters fall back to CPU activity. These are not battery percentages or total system power.
- Safari `.download` packages now show payload bytes and speed. Percentages appear only when usable total-size metadata exists. Folder scanning runs away from the UI thread.
- Export content-free diagnostics from Support. Bundled privacy, uninstall and license information is available offline.
- Clipboard load failures preserve existing data, including permission errors and missing keys. Settings changes cannot write history while a reload is pending.
- Codex refreshes/reconnects after wake, session-list requests can recover from timeout, and the executable locator supports the current desktop bundle location.
- Release configuration requires signed Sparkle feeds. Local tests use Sparkle’s real signing/verifying tools and disposable keys to reject tampered archives, wrong keys and modified feeds.

Includes the 0.2 native UI redesign, off-by-default session pinning, 120 ms pointer-exit grace, Quick Look, tray search and removal Undo.

No paid developer enrollment, notarization or public feed is included. Live Claude, AirDrop recipient delivery and the hardware/OS matrix still require their corresponding accounts/devices and permission tests.
