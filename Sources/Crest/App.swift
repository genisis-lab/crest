import SwiftUI
import AppKit
import Combine
import ServiceManagement
import CrestCore

enum NotchTab: String, CaseIterable, Identifiable {
    case overview = "Overview", agents = "Agents", tray = "Tray", clipboard = "Clipboard", notes = "Notes"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .agents: return "terminal"
        case .tray: return "tray"
        case .clipboard: return "doc.on.clipboard"
        case .notes: return "note.text"
        }
    }
}

/// A transient message in the collapsed notch. A level renders as a HUD bar.
struct Notice: Equatable {
    var text: String
    var symbol = "info.circle"
    var level: Double?
    var urgent = false
}

/// What the collapsed notch shows between its edges, in priority order.
enum LiveActivity: Equatable {
    case attention(String), timer, meeting(String), download, media
    /// Text-bearing activities need wider edges than the default icon pair.
    var wide: Bool { self != .media }
}

@MainActor final class AppModel: ObservableObject {
    let agents = AgentService()
    let tray = TrayService()
    let clipboard = ClipboardService()
    let downloads = FolderService()
    let screenshots = FolderService()
    let power = PowerService()
    let audio = AudioService()
    let brightness = BrightnessService()
    let hardwareKeys = HardwareKeyService()
    let calendar = CalendarService()
    let bluetooth = BluetoothService()
    let media = MediaService()
    let updates = UpdateService()
    let displays = DisplayPlacement()
    let shortcut = GlobalShortcut()
    let energy = AppEnergyService()
    let focus = FocusService()
    let awake = AwakeService()
    let notes = NotesService()
    @Published var expanded = false
    // Pinning is session-only and intentionally off on every launch.
    @Published var pinned = false
    @Published var tab = NotchTab.overview
    @Published var notice: Notice?
    @Published private(set) var liveActivity: LiveActivity?
    // True while a text field in the panel has focus, so the pointer leaving does not collapse it.
    @Published var editing = false
    @Published var glass = UserDefaults.standard.object(forKey: "glass") as? Bool ?? true { didSet { UserDefaults.standard.set(glass, forKey: "glass") } }
    @Published var hideFullScreen = UserDefaults.standard.object(forKey: "hideFullScreen") as? Bool ?? true { didSet { UserDefaults.standard.set(hideFullScreen, forKey: "hideFullScreen") } }
    @Published var notchHeight: CGFloat = 32
    @Published var collapsedWidth: CGFloat = 290
    @Published var cutoutWidth: CGFloat = 180
    @Published var interacting = false
    @Published var keyboardOpen = false
    @Published var settingsSection: SettingsSection = .general
    @Published var onboarding = !UserDefaults.standard.bool(forKey: "onboarded")
    var showSettings: (() -> Void)?
    private var cancellables = Set<AnyCancellable>()
    private var noticeTask: Task<Void, Never>?
    init() {
        let publishers = [agents.objectWillChange, tray.objectWillChange, clipboard.objectWillChange, downloads.objectWillChange, screenshots.objectWillChange, power.objectWillChange, audio.objectWillChange, brightness.objectWillChange, hardwareKeys.objectWillChange, calendar.objectWillChange, bluetooth.objectWillChange, media.objectWillChange, updates.objectWillChange, displays.objectWillChange, shortcut.objectWillChange, energy.objectWillChange, focus.objectWillChange, awake.objectWillChange]
        for publisher in publishers {
            publisher.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        }
        // objectWillChange fires before the new value is stored; evaluate after the run loop turn.
        let ticks = Timer.publish(every: 15, on: .main, in: .common).autoconnect().map { _ in () }
        Publishers.Merge(Publishers.MergeMany(publishers), ticks)
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.updateActivity() }.store(in: &cancellables)
        agents.onAttention = { [weak self] text in
            self?.alert(text, symbol: "exclamationmark.bubble.fill", urgent: true)
            if UserDefaults.standard.object(forKey: "attentionSound") as? Bool ?? true { NSSound(named: "Ping")?.play() }
        }
        power.onCharge = { [weak self] text in self?.alert(text, symbol: "bolt.fill") }
        audio.onChange = { [weak self] text in
            guard let self else { return }
            alert(text, symbol: audio.muted ? "speaker.slash.fill" : audio.volume < 0.34 ? "speaker.wave.1.fill" : "speaker.wave.3.fill", level: audio.muted ? 0 : Double(audio.volume))
        }
        brightness.onChange = { [weak self] text in
            guard let self else { return }
            alert(text, symbol: "sun.max.fill", level: Double(brightness.value))
        }
        hardwareKeys.onChange = { [weak self] text in
            guard let self else { return }
            if text.hasPrefix("Brightness") { alert(text, symbol: "sun.max.fill", level: Double(brightness.value)) }
            else { alert(text, symbol: audio.muted ? "speaker.slash.fill" : "speaker.wave.3.fill", level: audio.muted ? 0 : Double(audio.volume)) }
        }
        tray.onInteraction = { [weak self] value in self?.interacting = value }
        bluetooth.onConnect = { [weak self] text in self?.alert(text, symbol: "airpodspro") }
        focus.onFinish = { [weak self] in
            self?.alert("Focus session complete", symbol: "checkmark.circle.fill")
            if UserDefaults.standard.object(forKey: "timerSound") as? Bool ?? true { NSSound(named: "Glass")?.play() }
        }
        if UserDefaults.standard.bool(forKey: "clipboardEnabled") { clipboard.setEnabled(true) }
        if UserDefaults.standard.bool(forKey: "codexEnabled") { agents.connect(path: UserDefaults.standard.string(forKey: "codexPath") ?? AgentService.findCodex() ?? "", socket: UserDefaults.standard.string(forKey: "codexSocket") ?? "") }
        media.configure(enabled: UserDefaults.standard.bool(forKey: "mediaEnabled"), player: UserDefaults.standard.string(forKey: "mediaPlayer") ?? "System")
        brightness.enable(UserDefaults.standard.bool(forKey: "brightnessEnabled")); bluetooth.enable(UserDefaults.standard.bool(forKey: "bluetoothEnabled"))
        energy.configure(UserDefaults.standard.bool(forKey: "appEnergyEnabled"))
        screenshots.restore(tray: tray, screenshots: true); downloads.restore(tray: tray, screenshots: false)
    }
    func alert(_ text: String, symbol: String = "info.circle", level: Double? = nil, urgent: Bool = false) {
        if !urgent && agents.sessions.contains(where: { $0.state == "Needs you" }) { return }
        noticeTask?.cancel(); notice = Notice(text: text, symbol: symbol, level: level.map { min(1, max(0, $0)) }, urgent: urgent)
        if urgent { tab = .agents }
        // Level changes arrive in bursts while a key is held; a HUD clears sooner than a message.
        let duration: Duration = level == nil ? .seconds(5) : .milliseconds(1600)
        noticeTask = Task { try? await Task.sleep(for: duration); guard !Task.isCancelled else { return }; notice = nil }
    }
    func updateActivity(at now: Date = Date()) {
        var next: LiveActivity?
        if UserDefaults.standard.object(forKey: "liveActivities") as? Bool ?? true {
            if let waiting = agents.sessions.first(where: { $0.state == "Needs you" }) { next = .attention(waiting.provider) }
            else if focus.timer.isActive { next = .timer }
            else if let meeting = upcomingMeeting(at: now) { next = .meeting(meeting.id) }
            else if !downloads.downloads.isEmpty { next = .download }
            else if media.playing { next = .media }
        } else if media.playing { next = .media }
        if next != liveActivity { liveActivity = next }
    }
    /// A meeting from ten minutes before it starts until five minutes after.
    func upcomingMeeting(at now: Date = Date()) -> Meeting? {
        calendar.meetings.first { $0.start.timeIntervalSince(now) <= 600 && now.timeIntervalSince($0.start) <= 300 && $0.end > now }
    }
    func finishOnboarding() { onboarding = false; UserDefaults.standard.set(true, forKey: "onboarded") }
    func openSettings(_ section: SettingsSection) { settingsSection = section; showSettings?() }
}

@main struct CrestApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        Settings { SettingsView(model: delegate.model) }
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button("Settings…") { delegate.settings() }
                        .keyboardShortcut(",", modifiers: .command)
                }
            }
    }
}

@MainActor final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    let model = AppModel()
    private var panel: NotchPanel!
    private var settingsWindow: NSWindow?
    private var statusItem: NSStatusItem!
    private var sinks = Set<AnyCancellable>()
    private var visibilityTimer: Timer?
    private var chosenScreen: NSScreen?
    private let spring = PanelSpring()
    private var focusMenuItem: NSMenuItem?
    private var stopFocusItem: NSMenuItem?
    private var awakeMenuItem: NSMenuItem?
    private var awakeOffItem: NSMenuItem?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "mountain.2.fill", accessibilityDescription: "Crest"); statusItem.menu = buildMenu()
        panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.level = .statusBar; panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]; panel.hidesOnDeactivate = false; panel.isMovable = false
        panel.contentView = NSHostingView(rootView: NotchView(model: model))
        panel.delegate = self
        model.showSettings = { [weak self] in self?.settings() }
        model.displays.onChange = { [weak self] in self?.layout() }
        model.shortcut.onPress = { [weak self] in self?.toggle() }
        model.shortcut.configure(UserDefaults.standard.bool(forKey: "globalShortcutEnabled"))
        model.$expanded.combineLatest(model.$notice).sink { [weak self] _, _ in DispatchQueue.main.async { self?.layout() } }.store(in: &sinks)
        model.$liveActivity.combineLatest(model.$onboarding).sink { [weak self] _, _ in DispatchQueue.main.async { self?.layout() } }.store(in: &sinks)
        NotificationCenter.default.addObserver(self, selector: #selector(displayChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(checkVisibility), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        visibilityTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in Task { @MainActor in self?.checkVisibility() } }
        layout(); panel.orderFrontRegardless()
        if model.onboarding { model.expanded = true }
        else { model.alert("Welcome back", symbol: "mountain.2.fill") }
        // Only a smoke-test invocation exits automatically; ordinary launches remain running.
        if ProcessInfo.processInfo.arguments.contains("--smoke-test") { DispatchQueue.main.asyncAfter(deadline: .now() + 3) { NSApp.terminate(nil) } }
    }
    func layout() {
        guard panel != nil, let screen = model.displays.screen else { return }
        chosenScreen = screen
        let left = screen.auxiliaryTopLeftArea, right = screen.auxiliaryTopRightArea
        let cutoutWidth = max(180, (right?.minX ?? 0) - (left?.maxX ?? 0))
        model.notchHeight = max(30, screen.safeAreaInsets.top)
        model.cutoutWidth = cutoutWidth
        model.collapsedWidth = cutoutWidth + 96
        // Live activities with text (timer, meeting, download, agent) grow the edges beside the cutout.
        let collapsed = model.collapsedWidth + (model.liveActivity?.wide == true ? 72 : 0)
        let width: CGFloat = model.expanded ? min(568, screen.frame.width - 24) : model.notice == nil ? collapsed : max(410, collapsed)
        let contentHeight: CGFloat = model.onboarding ? 476 : 484
        let height: CGFloat = model.expanded ? min(contentHeight + model.notchHeight, screen.visibleFrame.height - 20) : model.notchHeight + (model.notice == nil ? 5 : 34)
        let rect = NSRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - height, width: width, height: height)
        spring.move(panel, to: rect, immediately: panel.frame.width == 0 || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }
    @objc func displayChanged() { model.displays.refresh(); layout(); checkVisibility() }
    @objc func didWake() { displayChanged(); model.agents.resumeAfterWake(); model.power.refresh(); model.calendar.refresh(); model.audio.refresh(); model.focus.refresh() }
    @objc func checkVisibility() {
        guard panel != nil else { return }
        var hide = false
        if model.hideFullScreen, let screen = chosenScreen, let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
           let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            // Bounds-only heuristic; do not request screen recording or read window titles.
            let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 ?? CGMainDisplayID()
            let bounds = CGDisplayBounds(displayID)
            hide = windows.contains { item in
                guard item[kCGWindowOwnerPID as String] as? pid_t == app.processIdentifier, item[kCGWindowLayer as String] as? Int == 0,
                      let raw = item[kCGWindowBounds as String] as? [String: Any], let frame = CGRect(dictionaryRepresentation: raw as CFDictionary) else { return false }
                return abs(frame.origin.x - bounds.origin.x) < 2 && abs(frame.origin.y - bounds.origin.y) < 2 && abs(frame.width - bounds.width) < 2 && abs(frame.height - bounds.height) < 2
            }
        }
        if hide { panel.orderOut(nil) } else if !panel.isVisible { panel.orderFrontRegardless() }
    }
    @objc func toggle() {
        model.expanded.toggle(); model.keyboardOpen = model.expanded
        if model.expanded { NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil) }
    }
    func windowDidResignKey(_ notification: Notification) {
        // Clicking another app ends text editing; the panel may then collapse normally.
        if model.editing { model.editing = false; panel.makeFirstResponder(nil) }
        if model.keyboardOpen && !model.pinned && !model.interacting {
            model.keyboardOpen = false; model.expanded = false
        }
    }
    @objc func settings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 660), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Crest Settings"; window.contentView = NSHostingView(rootView: SettingsView(model: model)); window.isReleasedWhenClosed = false; window.center(); settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true); settingsWindow?.makeKeyAndOrderFront(nil)
    }
    @objc func updates() { if model.updates.configured { model.updates.check() } else { model.openSettings(.updates) } }
    @objc func quit() { model.agents.disconnect(); NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) { model.agents.disconnect(); model.shortcut.stop(); model.notes.save(); model.awake.disable() }
    private func buildMenu() -> NSMenu {
        let menu = NSMenu(); menu.delegate = self
        menu.addItem(menuItem("Open Crest", #selector(toggle)))
        menu.addItem(.separator())
        let focus = NSMenu(); focus.autoenablesItems = false
        for minutes in FocusService.presets + [60] { focus.addItem(menuItem("\(minutes) minutes", #selector(startFocus(_:)), tag: minutes)) }
        focus.addItem(.separator())
        let stop = menuItem("Stop Timer", #selector(stopFocus)); focus.addItem(stop); stopFocusItem = stop
        let focusItem = NSMenuItem(title: "Focus Timer", action: nil, keyEquivalent: ""); focusItem.submenu = focus; menu.addItem(focusItem); focusMenuItem = focusItem
        let awake = NSMenu(); awake.autoenablesItems = false
        for (index, option) in AwakeService.durations.enumerated() { awake.addItem(menuItem(option.0, #selector(startAwake(_:)), tag: index)) }
        awake.addItem(.separator())
        let off = menuItem("Turn Off", #selector(stopAwake)); awake.addItem(off); awakeOffItem = off
        let awakeItem = NSMenuItem(title: "Keep Mac Awake", action: nil, keyEquivalent: ""); awakeItem.submenu = awake; menu.addItem(awakeItem); awakeMenuItem = awakeItem
        menu.addItem(.separator())
        menu.addItem(menuItem("Settings…", #selector(settings), key: ","))
        menu.addItem(menuItem("Check for Updates…", #selector(updates)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit Crest", #selector(quit), key: "q"))
        return menu
    }
    private func menuItem(_ title: String, _ action: Selector, key: String = "", tag: Int = 0) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = self; item.tag = tag; return item
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        let timer = model.focus.timer
        focusMenuItem?.title = timer.isActive ? "Focus Timer · \(TimeFormat.compact(timer.remaining(at: Date()))) \(timer.isPaused ? "paused" : "left")" : "Focus Timer"
        stopFocusItem?.isEnabled = timer.isActive
        awakeMenuItem?.state = model.awake.active ? .on : .off
        awakeOffItem?.isEnabled = model.awake.active
    }
    @objc func startFocus(_ sender: NSMenuItem) { model.focus.start(minutes: sender.tag) }
    @objc func stopFocus() { model.focus.stop() }
    @objc func startAwake(_ sender: NSMenuItem) { if AwakeService.durations.indices.contains(sender.tag) { model.awake.enable(for: AwakeService.durations[sender.tag].1) } }
    @objc func stopAwake() { model.awake.disable() }
}
