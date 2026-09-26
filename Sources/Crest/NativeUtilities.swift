import AppKit
import Carbon
import CrestCore

struct DisplayChoice: Identifiable {
    let id: String
    let name: String
}

@MainActor final class DisplayPlacement: ObservableObject {
    @Published private(set) var choices: [DisplayChoice] = []
    @Published var selected = UserDefaults.standard.string(forKey: "preferredDisplay") ?? "automatic" {
        didSet { UserDefaults.standard.set(selected, forKey: "preferredDisplay"); onChange?() }
    }
    var onChange: (() -> Void)?
    init() { refresh() }
    static func identifier(_ screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }
    func refresh() {
        choices = NSScreen.screens.compactMap { screen in
            Self.identifier(screen).map { DisplayChoice(id: $0, name: screen.localizedName) }
        }
    }
    var screen: NSScreen? {
        NSScreen.screens.first { Self.identifier($0) == selected }
            ?? NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
            ?? NSScreen.main ?? NSScreen.screens.first
    }
    var preferredUnavailable: Bool { selected != "automatic" && !choices.contains { $0.id == selected } }
}

/// Registers one shortcut with the OS; does not observe ordinary keyboard input.
@MainActor final class GlobalShortcut: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var status = "Control–Option–Space opens Crest from any app."
    var onPress: (() -> Void)?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    func configure(_ requested: Bool) {
        stop()
        guard requested else { status = "Control–Option–Space opens Crest from any app."; return }
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, pointer in
            guard let pointer else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated { Unmanaged<GlobalShortcut>.fromOpaque(pointer).takeUnretainedValue().onPress?() }
            return noErr
        }, 1, &event, context, &handler)
        guard installed == noErr else { status = "The keyboard shortcut could not be registered."; return }
        let identifier = EventHotKeyID(signature: 0x43525354, id: 1)
        let registered = RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey), identifier, GetApplicationEventTarget(), 0, &hotKey)
        guard registered == noErr else { stop(); status = "Control–Option–Space is unavailable. Another app may already use it."; return }
        enabled = true; status = "Control–Option–Space opens Crest. Escape closes it."
    }
    func stop() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil; handler = nil; enabled = false
    }
}

@MainActor enum Diagnostics {
    static func report(_ model: AppModel) -> DiagnosticsReport {
        DiagnosticsReport(appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: architecture,
            displayCount: NSScreen.screens.count,
            hasNotchedDisplay: NSScreen.screens.contains { $0.safeAreaInsets.top > 0 },
            features: ["codexConnected": model.agents.connected, "clipboardEnabled": model.clipboard.enabled,
                "calendarEnabled": model.calendar.enabled, "updatesConfigured": model.updates.configured,
                "mediaAvailable": model.media.available, "audioAvailable": model.audio.available,
                "brightnessAvailable": model.brightness.available, "hardwareKeysEnabled": model.hardwareKeys.enabled,
                "globalShortcutEnabled": model.shortcut.enabled,
                "reduceMotion": NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                "reduceTransparency": NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency])
    }
    static func export(_ model: AppModel) -> String {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Crest-diagnostics.json"
        panel.allowedContentTypes = [.json]
        panel.message = "Includes only version, hardware category, accessibility settings, and connection flags. No history, file paths, account information, or content."
        guard panel.runModal() == .OK, let url = panel.url else { return "Export cancelled." }
        do { try report(model).data().write(to: url, options: .atomic); return "Diagnostics saved. Nothing was uploaded." }
        catch { return "Could not save diagnostics: \(error.localizedDescription)" }
    }
    private static var architecture: String {
        #if arch(arm64)
        return "Apple Silicon"
        #else
        return "Intel"
        #endif
    }
}
