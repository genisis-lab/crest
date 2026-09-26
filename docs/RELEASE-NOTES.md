# Crest 0.3.0 — development build

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
