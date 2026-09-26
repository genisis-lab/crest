import SwiftUI
import AppKit
import ServiceManagement

enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General", connections = "Connections", files = "Files & Privacy", media = "Media & System", updates = "Updates", support = "Support"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .connections: return "point.3.connected.trianglepath.dotted"
        case .files: return "lock.shield"
        case .media: return "slider.horizontal.3"
        case .updates: return "arrow.down.circle"
        case .support: return "checkmark.shield"
        }
    }
    var detail: String {
        switch self {
        case .general: return "Make Crest feel at home on your Mac."
        case .connections: return "Bring your agents and upcoming meetings together."
        case .files: return "Choose what stays within reach, and what stays private."
        case .media: return "Your music, display, and everyday controls."
        case .updates: return "Keep Crest up to date."
        case .support: return "Connection status and information about this build."
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @AppStorage("codexPath") private var codexPath = AgentService.findCodex() ?? ""
    @AppStorage("codexSocket") private var codexSocket = ""
    @AppStorage("codexEnabled") private var codexEnabled = false
    @AppStorage("mediaEnabled") private var mediaEnabled = false
    @AppStorage("mediaPlayer") private var mediaPlayer = "System"
    @AppStorage("brightnessEnabled") private var brightnessEnabled = false
    @AppStorage("bluetoothEnabled") private var bluetoothEnabled = false
    @State private var setupStatus = ""
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var loginError = ""
    @State private var diagnosticsStatus = ""
    @State private var helpDocument: HelpDocument?
    @AppStorage("showMedia") private var showMedia = true
    @AppStorage("showUsage") private var showUsage = true
    @AppStorage("showSystem") private var showSystem = true
    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $model.settingsSection) {
                    ForEach(SettingsSection.allCases) { section in
                        Label(section.rawValue, systemImage: section.symbol).tag(section)
                    }
                }.listStyle(.sidebar)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Crest").font(.system(size: 12, weight: .semibold))
                    Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            }.frame(width: 180)
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                switch model.settingsSection {
                case .general: general
                case .connections: connections
                case .files: files
                case .media: media
                case .updates: updates
                case .support: support
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }.frame(minWidth: 740, minHeight: 600)
            .sheet(item: $helpDocument) { document in
                VStack(alignment: .leading, spacing: 16) {
                    HStack { Text(document.title).font(.title2.bold()); Spacer(); Button("Done") { helpDocument = nil }.keyboardShortcut(.cancelAction) }
                    ScrollView { Text(document.contents).font(.system(size: 13)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                }.padding(24).frame(width: 620, height: 520)
            }
    }
    private var general: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.settingsSection.rawValue).font(.system(size: 23, weight: .semibold))
                    Text(model.settingsSection.detail).font(.system(size: 12)).foregroundStyle(.secondary)
                }.padding(.vertical, 8)
            }
                Section("Appearance") { Toggle("Glass appearance", isOn: $model.glass); Text("Liquid Glass on macOS 26 and later; native material on older systems. Respects Reduce Transparency and Increase Contrast.").font(.caption).foregroundStyle(.secondary); Toggle("Hide in full-screen apps", isOn: $model.hideFullScreen); Toggle("Keep the notch expanded", isOn: $model.pinned); Button("Show welcome tour") { model.onboarding = true; model.expanded = true } }
                Section("Overview") {
                    Toggle("Now Playing", isOn: $showMedia)
                    Toggle("Agent usage", isOn: $showUsage)
                    Toggle("Sound, brightness, and battery", isOn: $showSystem)
                    Text("Choose the modules that appear when you open Crest.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Display & keyboard") {
                    Picker("Show Crest on", selection: Binding(get: { model.displays.selected }, set: { model.displays.selected = $0 })) {
                        Text("Automatic").tag("automatic")
                        ForEach(model.displays.choices) { Text($0.name).tag($0.id) }
                        if model.displays.preferredUnavailable { Text("Preferred display (disconnected)").tag(model.displays.selected) }
                    }
                    if model.displays.preferredUnavailable { Text("Using an available display until your preferred display reconnects.").font(.caption).foregroundStyle(.secondary) }
                    Toggle("Open with Control–Option–Space", isOn: Binding(get: { model.shortcut.enabled }, set: { value in
                        model.shortcut.configure(value)
                        UserDefaults.standard.set(model.shortcut.enabled, forKey: "globalShortcutEnabled")
                    }))
                    Text(model.shortcut.status).font(.caption).foregroundStyle(.secondary)
                }
                Section("Startup") {
                    Toggle("Open Crest at login", isOn: $loginEnabled).onChange(of: loginEnabled) { _, value in
                        do { if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; loginError = "" } catch { loginError = error.localizedDescription; loginEnabled = SMAppService.mainApp.status == .enabled }
                    }
                    if !loginError.isEmpty { Text(loginError).foregroundStyle(.orange) }
                }
                Section("About Crest") { Text("Native Swift for macOS 14 and later"); Text("A local utility for agent activity, files and everyday controls.").foregroundStyle(.secondary); Text("Hover the notch to open. Pin it to keep it visible. Escape collapses it.").foregroundStyle(.secondary) }
        }.formStyle(.grouped)
    }
    private var connections: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.settingsSection.rawValue).font(.system(size: 23, weight: .semibold))
                    Text(model.settingsSection.detail).font(.system(size: 12)).foregroundStyle(.secondary)
                }.padding(.vertical, 8)
            }
                Section("Codex") {
                    TextField("Executable", text: $codexPath)
                    DisclosureGroup("Advanced session monitoring") { TextField("Shared server socket", text: $codexSocket) }
                    Text("Usage works through your existing Codex login. Session monitoring requires a shared server socket; a standalone connection cannot observe unrelated terminals.").font(.caption).foregroundStyle(.secondary)
                    HStack { Button("Connect / reconnect") { codexEnabled = true; model.agents.connect(path: codexPath, socket: codexSocket) }; Button("Disconnect") { codexEnabled = false; model.agents.disconnect() } }
                    Text(model.agents.status).font(.caption)
                }
                Section("Claude Code") {
                    Text("Install local event hooks and a usage status-line bridge. Existing hooks are preserved; an existing status-line command is forwarded. This does not approve agent actions.").font(.caption).foregroundStyle(.secondary)
                    HStack { Button("Install alerts + usage") { setup { try ClaudeSetup.install(includeStatus: true) } }; Button("Alerts only") { setup { try ClaudeSetup.install(includeStatus: false) } }; Button("Remove integration") { setup { try ClaudeSetup.uninstall() } } }
                    Text("Usage requires Claude Code 2.1.251+ and quota fields from the provider. Uses your existing Claude session.").font(.caption).foregroundStyle(.secondary)
                    if !setupStatus.isEmpty { Text(setupStatus).font(.caption) }
                }
                Section("Calendar") { HStack { Button("Connect calendars") { Task { await model.calendar.connect() } }; Button("Disconnect") { model.calendar.disconnect() } }; Text(model.calendar.status).font(.caption); ForEach(model.calendar.meetings) { MeetingRow(meeting: $0) } }
        }.formStyle(.grouped)
    }
    private var files: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.settingsSection.rawValue).font(.system(size: 23, weight: .semibold))
                    Text(model.settingsSection.detail).font(.system(size: 12)).foregroundStyle(.secondary)
                }.padding(.vertical, 8)
            }
                Section("Encrypted clipboard") {
                    Toggle("Record clipboard history", isOn: Binding(get: { model.clipboard.enabled || model.clipboard.loading }, set: { model.clipboard.setEnabled($0, allowAuthentication: true) }))
                    if model.clipboard.loading { ProgressView("Opening encrypted history…").controlSize(.small) }
                    Picker("Keep unpinned items", selection: Binding(get: { model.clipboard.days }, set: { model.clipboard.days = $0 })) { ForEach([1, 7, 30, 90, 365], id: \.self) { Text("\($0) days").tag($0) } }
                    Text("Pinned items remain until deleted. History is encrypted on this Mac. Password managers and concealed clipboard types are always excluded.").font(.caption).foregroundStyle(.secondary)
                    Text("Ignore apps (one bundle identifier per line)").font(.caption)
                    TextEditor(text: Binding(get: { model.clipboard.exclusions }, set: { model.clipboard.exclusions = $0 })).font(.system(.caption, design: .monospaced)).frame(height: 90)
                    if let error = model.clipboard.error { Text(error).font(.caption).foregroundStyle(.orange) }
                }
                Section("Screenshot imports") { HStack { Button("Choose screenshot folder…") { model.screenshots.choose(tray: model.tray, screenshots: true) }; Button("Stop") { model.screenshots.stop() } }; Text(model.screenshots.status).font(.caption) }
                Section("Downloads") { HStack { Button("Choose download folder…") { model.downloads.choose(tray: model.tray, screenshots: false) }; Button("Stop") { model.downloads.stop() } }; Text(model.downloads.status).font(.caption); Text("Shows partial-file and Safari download-package sizes and growth speed. A percentage appears only when the browser provides a usable total.").font(.caption).foregroundStyle(.secondary) }
        }.formStyle(.grouped)
    }
    private var media: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.settingsSection.rawValue).font(.system(size: 23, weight: .semibold))
                    Text(model.settingsSection.detail).font(.system(size: 12)).foregroundStyle(.secondary)
                }.padding(.vertical, 8)
            }
                Section("Now playing") {
                    Toggle("Enable music controls", isOn: $mediaEnabled).onChange(of: mediaEnabled) { _, _ in configureMedia() }
                    Picker("Player adapter", selection: $mediaPlayer) { Text("System player (experimental)").tag("System"); Text("Apple Music").tag("Music"); Text("Spotify").tag("Spotify") }.onChange(of: mediaPlayer) { _, _ in configureMedia() }
                    Text(model.media.status).font(.caption)
                    Text("The system adapter attempts to support Music, Spotify, Podcasts, TV and IINA. It uses a compatibility API that may be blocked by macOS. Direct Music/Spotify adapters use Automation permission.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Display & audio") {
                    Toggle("Enable brightness adapter (experimental)", isOn: $brightnessEnabled).onChange(of: brightnessEnabled) { _, value in model.brightness.enable(value) }
                    Toggle("Replace hardware-key overlays (experimental)", isOn: Binding(get: { model.hardwareKeys.enabled }, set: { model.hardwareKeys.enable($0, audio: model.audio, brightness: model.brightness) }))
                    Text(model.hardwareKeys.status).font(.caption).foregroundStyle(.secondary)
                    Text("Requires Accessibility permission. Enable again after each launch. Ordinary typing is not observed.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Bluetooth") { Toggle("Monitor AirPods and battery devices", isOn: $bluetoothEnabled).onChange(of: bluetoothEnabled) { _, value in model.bluetooth.enable(value) }; Text(model.bluetooth.status).font(.caption) }
                Section("App power") {
                    Toggle("Show app power estimates", isOn: Binding(get: { model.energy.enabled }, set: { value in
                        UserDefaults.standard.set(value, forKey: "appEnergyEnabled"); model.energy.configure(value)
                    }))
                    Text("Uses macOS process energy counters and groups readable helpers in each app bundle. Estimates omit system services and unreported hardware energy; they are not battery percentages. Names and readings stay in memory on this Mac.").font(.caption).foregroundStyle(.secondary)
                    Text(model.energy.status).font(.caption)
                }
        }.formStyle(.grouped)
    }
    private var updates: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.settingsSection.rawValue).font(.system(size: 23, weight: .semibold))
                    Text(model.settingsSection.detail).font(.system(size: 12)).foregroundStyle(.secondary)
                }.padding(.vertical, 8)
            }
                Section("Software updates") {
                    Text("Powered by Sparkle 2.10").font(.headline)
                    Text(model.updates.status).foregroundStyle(.secondary)
                    Toggle("Automatically check for updates", isOn: Binding(get: { model.updates.automatic }, set: { model.updates.automatic = $0 })).disabled(!model.updates.configured)
                    Toggle("Include beta releases", isOn: Binding(get: { model.updates.beta }, set: { model.updates.beta = $0 })).disabled(!model.updates.configured)
                    Button("Check for Updates…") { model.updates.check() }.disabled(!model.updates.configured)
                    Text("Automatic updates will become available with a signed release. This development build can be replaced manually without deleting your local data.").font(.caption).foregroundStyle(.secondary)
                }
        }.formStyle(.grouped)
    }
    private var support: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.settingsSection.rawValue).font(.system(size: 23, weight: .semibold))
                    Text(model.settingsSection.detail).font(.system(size: 12)).foregroundStyle(.secondary)
                }.padding(.vertical, 8)
            }
            Section("Connections") {
                LabeledContent("Codex usage", value: model.agents.connected ? "Connected" : "Disconnected")
                LabeledContent("Claude usage", value: model.agents.claude == nil ? "No data received" : "Data received")
                LabeledContent("Calendar", value: model.calendar.enabled ? "Connected" : "Off")
                LabeledContent("Clipboard recording", value: model.clipboard.enabled ? "On · encrypted" : "Off")
            }
            Section("This build") {
                LabeledContent("Updates", value: model.updates.configured ? "Configured" : "Development build")
                Text("Media compatibility, AirPods readings, and hardware-key overlays depend on your macOS version and device.").font(.caption).foregroundStyle(.secondary)
                Text("Codex session alerts require a shared server. App power estimates and download percentages appear only when macOS or the browser supplies the necessary data.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Help") {
                Button("Export diagnostics…") { diagnosticsStatus = Diagnostics.export(model) }
                Text("Exports version and connection flags only. No clipboard content, calendar entries, file paths, or account information. You choose where to save it.").font(.caption).foregroundStyle(.secondary)
                if !diagnosticsStatus.isEmpty { Text(diagnosticsStatus).font(.caption) }
                HStack {
                    Button("Privacy") { helpDocument = HelpDocument(title: "Privacy", resource: "Privacy") }
                    Button("Uninstall") { helpDocument = HelpDocument(title: "Uninstall Crest", resource: "Uninstall") }
                    Button("Third-party licenses") { helpDocument = HelpDocument(title: "Third-party licenses", resource: "ThirdPartyNotices") }
                }
                Link("Feature coverage and known limitations", destination: URL(string: "https://github.com/genisis-lab/crest/blob/main/docs/FEATURES.md")!)
                Link("Source and release information", destination: URL(string: "https://github.com/genisis-lab/crest")!)
                Text("Repository access is required. Crest does not upload diagnostics, calendar entries, or clipboard history.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
    private func setup(_ action: () throws -> String) { do { setupStatus = try action() } catch { setupStatus = error.localizedDescription } }
    private func configureMedia() { model.media.configure(enabled: mediaEnabled, player: mediaPlayer) }
}

private struct HelpDocument: Identifiable {
    let title: String
    let resource: String
    var id: String { resource }
    var contents: String {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "txt"), let text = try? String(contentsOf: url, encoding: .utf8) else { return "This document is unavailable. Rebuild or reinstall the complete Crest.app bundle." }
        return text
    }
}
