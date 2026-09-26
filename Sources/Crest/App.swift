import SwiftUI
import AppKit
import Combine
import ServiceManagement

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
    @Published var expanded = false
    // Pinning is session-only and intentionally off on every launch.
    @Published var pinned = false
    @Published var tab = "Overview"
    @Published var notice: String?
    @Published var glass = UserDefaults.standard.object(forKey: "glass") as? Bool ?? true { didSet { UserDefaults.standard.set(glass, forKey: "glass") } }
    @Published var hideFullScreen = UserDefaults.standard.object(forKey: "hideFullScreen") as? Bool ?? true { didSet { UserDefaults.standard.set(hideFullScreen, forKey: "hideFullScreen") } }
    @Published var notchHeight: CGFloat = 32
    @Published var collapsedWidth: CGFloat = 290
    @Published var cutoutWidth: CGFloat = 180
    @Published var interacting = false
    @Published var settingsSection: SettingsSection = .general
    @Published var onboarding = !UserDefaults.standard.bool(forKey: "onboarded")
    var showSettings: (() -> Void)?
    private var cancellables = Set<AnyCancellable>()
    private var noticeTask: Task<Void, Never>?
    init() {
        for publisher in [agents.objectWillChange, tray.objectWillChange, clipboard.objectWillChange, downloads.objectWillChange, screenshots.objectWillChange, power.objectWillChange, audio.objectWillChange, brightness.objectWillChange, hardwareKeys.objectWillChange, calendar.objectWillChange, bluetooth.objectWillChange, media.objectWillChange, updates.objectWillChange] {
            publisher.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        }
        agents.onAttention = { [weak self] text in self?.alert(text, urgent: true) }
        power.onCharge = { [weak self] text in self?.alert(text) }
        audio.onChange = { [weak self] text in self?.alert(text) }
        brightness.onChange = { [weak self] text in self?.alert(text) }
        hardwareKeys.onChange = { [weak self] text in self?.alert(text) }
        tray.onInteraction = { [weak self] value in self?.interacting = value }
        bluetooth.onConnect = { [weak self] text in self?.alert(text) }
        if UserDefaults.standard.bool(forKey: "clipboardEnabled") { clipboard.setEnabled(true) }
        if UserDefaults.standard.bool(forKey: "codexEnabled") { agents.connect(path: UserDefaults.standard.string(forKey: "codexPath") ?? AgentService.findCodex() ?? "", socket: UserDefaults.standard.string(forKey: "codexSocket") ?? "") }
        media.configure(enabled: UserDefaults.standard.bool(forKey: "mediaEnabled"), player: UserDefaults.standard.string(forKey: "mediaPlayer") ?? "System")
        brightness.enable(UserDefaults.standard.bool(forKey: "brightnessEnabled")); bluetooth.enable(UserDefaults.standard.bool(forKey: "bluetoothEnabled"))
        screenshots.restore(tray: tray, screenshots: true); downloads.restore(tray: tray, screenshots: false)
    }
    func alert(_ text: String, urgent: Bool = false) {
        if !urgent && agents.sessions.contains(where: { $0.state == "Needs you" }) { return }
        noticeTask?.cancel(); notice = text
        if urgent { tab = "Agents" }
        noticeTask = Task { try? await Task.sleep(for: .seconds(5)); guard !Task.isCancelled else { return }; notice = nil }
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

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var panel: NotchPanel!
    private var settingsWindow: NSWindow?
    private var statusItem: NSStatusItem!
    private var sinks = Set<AnyCancellable>()
    private var visibilityTimer: Timer?
    private var chosenScreen: NSScreen?
    private let spring = PanelSpring()
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let menu = NSMenu()
        for (title, action, key) in [("Open Crest", #selector(toggle), ""), ("Settings…", #selector(settings), ","), ("Check for Updates…", #selector(updates), ""), ("Quit Crest", #selector(quit), "q")] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = self; menu.addItem(item)
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "mountain.2.fill", accessibilityDescription: "Crest"); statusItem.menu = menu
        panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.level = .statusBar; panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]; panel.hidesOnDeactivate = false; panel.isMovable = false
        panel.contentView = NSHostingView(rootView: NotchView(model: model))
        model.showSettings = { [weak self] in self?.settings() }
        model.$expanded.combineLatest(model.$notice).sink { [weak self] _, _ in DispatchQueue.main.async { self?.layout() } }.store(in: &sinks)
        model.$tab.combineLatest(model.$onboarding).sink { [weak self] _, _ in DispatchQueue.main.async { self?.layout() } }.store(in: &sinks)
        NotificationCenter.default.addObserver(self, selector: #selector(displayChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(displayChanged), name: NSWorkspace.didWakeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(checkVisibility), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        visibilityTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in Task { @MainActor in self?.checkVisibility() } }
        layout(); panel.orderFrontRegardless()
        if model.onboarding { model.expanded = true }
        else { model.alert("Welcome back") }
        // Only a smoke-test invocation exits automatically; ordinary launches remain running.
        if ProcessInfo.processInfo.arguments.contains("--smoke-test") { DispatchQueue.main.asyncAfter(deadline: .now() + 3) { NSApp.terminate(nil) } }
    }
    func layout() {
        guard panel != nil, let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else { return }
        chosenScreen = screen
        let left = screen.auxiliaryTopLeftArea, right = screen.auxiliaryTopRightArea
        let cutoutWidth = max(180, (right?.minX ?? 0) - (left?.maxX ?? 0))
        model.notchHeight = max(30, screen.safeAreaInsets.top)
        model.cutoutWidth = cutoutWidth
        model.collapsedWidth = cutoutWidth + 96
        let width: CGFloat = model.expanded ? min(568, screen.frame.width - 24) : model.notice == nil ? model.collapsedWidth : max(410, model.collapsedWidth)
        let contentHeight: CGFloat = model.onboarding ? 460 : model.tab == "Overview" ? 438 : 488
        let height: CGFloat = model.expanded ? min(contentHeight + model.notchHeight, screen.visibleFrame.height - 20) : model.notchHeight + (model.notice == nil ? 5 : 34)
        let rect = NSRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - height, width: width, height: height)
        spring.move(panel, to: rect, immediately: panel.frame.width == 0 || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }
    @objc func displayChanged() { layout(); checkVisibility() }
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
    @objc func toggle() { model.expanded.toggle(); if model.expanded { panel.makeKeyAndOrderFront(nil) } }
    @objc func settings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 660), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Crest Settings"; window.contentView = NSHostingView(rootView: SettingsView(model: model)); window.isReleasedWhenClosed = false; window.center(); settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true); settingsWindow?.makeKeyAndOrderFront(nil)
    }
    @objc func updates() { if model.updates.configured { model.updates.check() } else { model.openSettings(.updates) } }
    @objc func quit() { model.agents.disconnect(); NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) { model.agents.disconnect() }
}
