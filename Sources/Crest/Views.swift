import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ServiceManagement
import CrestCore

private let coral = Color(red: 1, green: 0.54, blue: 0.38)
private let lilac = Color(red: 0.71, green: 0.65, blue: 1)

struct NotchView: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var collapse: Task<Void, Never>?
    @State private var dropping = false
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: model.agents.sessions.contains(where: { $0.state == "Needs you" }) ? "sparkle" : "mountain.2.fill")
                    .foregroundStyle(model.agents.sessions.contains(where: { $0.state == "Needs you" }) ? Color.pink : coral)
                Spacer(minLength: 180)
                if model.media.playing { Image(systemName: "waveform").foregroundStyle(lilac).symbolEffect(.variableColor.iterative, options: .repeating, isActive: !reduceMotion).accessibilityLabel("Playing") }
                else if let percent = model.power.percent { Text("\(percent)%").font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.65)) }
            }
            .padding(.horizontal, 19).frame(height: model.notchHeight)
            .contentShape(Rectangle()).onTapGesture { model.expanded.toggle() }
            .accessibilityElement(children: .ignore).accessibilityLabel(model.expanded ? "Collapse Crest" : "Open Crest")
            .accessibilityAddTraits(.isButton).accessibilityAction { model.expanded.toggle() }
            if model.expanded {
                if model.onboarding { welcome }
                else {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Crest").font(.system(size: 25, weight: .semibold, design: .rounded))
                            Text("A little more from your Mac.").font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
                        }
                        Spacer()
                        Button { model.pinned.toggle() } label: { Image(systemName: model.pinned ? "pin.fill" : "pin") }.help("Keep Crest open").tint(model.pinned ? coral : .gray)
                        Button { model.showSettings?() } label: { Image(systemName: "gearshape") }.help("Settings")
                        Button { model.pinned = false; model.expanded = false } label: { Image(systemName: "chevron.up") }.help("Collapse")
                    }.buttonStyle(.plain).padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 20)
                    Picker("Section", selection: $model.tab) {
                        ForEach(["Overview", "Agents", "Tray", "Clipboard"], id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }.pickerStyle(.segmented).labelsHidden().padding(.horizontal, 20).accessibilityLabel("Section")
                    ScrollView {
                        Group {
                            switch model.tab {
                            case "Agents": AgentsView(service: model.agents, settings: { model.showSettings?() })
                            case "Tray": TrayView(service: model.tray)
                            case "Clipboard": ClipboardView(service: model.clipboard, settings: { model.showSettings?() })
                            default: OverviewView(model: model)
                            }
                        }.padding(20)
                    }.scrollIndicators(.hidden)
                    HStack(spacing: 6) {
                        Circle().fill(model.agents.sessions.contains(where: { $0.state == "Needs you" }) ? .pink : .green.opacity(0.8)).frame(width: 5, height: 5)
                        Text(model.notice ?? "Private by default · On your Mac").lineLimit(1)
                        Spacer()
                        Text("0.1").foregroundStyle(.white.opacity(0.3))
                    }.font(.system(size: 10)).foregroundStyle(.white.opacity(0.7)).padding(.horizontal, 23).padding(.bottom, 15)
                }
            } else if let notice = model.notice {
                Text(notice).font(.system(size: 12, weight: .medium)).foregroundStyle(coral).padding(.bottom, 12).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .modifier(NotchMaterial(enabled: model.glass && model.expanded, expanded: model.expanded))
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: model.expanded ? 25 : 14, bottomTrailingRadius: model.expanded ? 25 : 14))
        .overlay(alignment: .bottom) { if dropping { RoundedRectangle(cornerRadius: 24).stroke(coral, lineWidth: 2) } }
        .preferredColorScheme(.dark)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1), value: model.tab)
        .onHover { inside in
            collapse?.cancel()
            if inside { model.expanded = true }
            else if !model.pinned && !model.onboarding {
                collapse = Task { try? await Task.sleep(for: .milliseconds(700)); if !Task.isCancelled && !dropping { model.expanded = false } }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropping) { providers in
            model.expanded = true; model.tab = "Tray"
            for provider in providers { provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url = (item as? URL) ?? (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                if let url { Task { @MainActor in model.tray.add([url]) } }
            } }
            return !providers.isEmpty
        }
        .onExitCommand { model.pinned = false; model.expanded = false }
    }
    private var welcome: some View {
        VStack(alignment: .leading, spacing: 22) {
            Image(systemName: "mountain.2.fill").font(.system(size: 34)).foregroundStyle(coral)
            Text("Meet your new\npoint of focus.").font(.system(size: 32, weight: .semibold, design: .rounded))
            Text("Agent alerts, useful little controls, and a place for the things you're working with. Right here, above it all.").font(.system(size: 14)).foregroundStyle(.white.opacity(0.7)).lineSpacing(4)
            VStack(alignment: .leading, spacing: 12) {
                Label("Hover to open. Move away to tuck it back.", systemImage: "cursorarrow")
                Label("Drop files here to keep them within reach.", systemImage: "tray")
                Label("Connect Claude and Codex in Settings.", systemImage: "sparkles")
            }.font(.system(size: 12)).foregroundStyle(.white.opacity(0.75))
            HStack {
                Button("Make yourself at home") { model.finishOnboarding() }.buttonStyle(.borderedProminent).tint(coral).foregroundStyle(.black)
                Button("Set up integrations") { model.finishOnboarding(); model.showSettings?() }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.7))
            }
            Text("Clipboard and calendars stay off until you enable them.").font(.system(size: 10)).foregroundStyle(.white.opacity(0.7))
        }.padding(28).frame(maxHeight: .infinity, alignment: .top)
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme
    var body: some View { content.padding(15).frame(maxWidth: .infinity, alignment: .leading).background(scheme == .dark ? Color.black.opacity(0.55) : Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 15)).overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.065), lineWidth: 1)) }
}
struct EmptyCard: View {
    var icon: String; var title: String; var detail: String
    var body: some View { VStack(spacing: 10) { Image(systemName: icon).font(.system(size: 26)).foregroundStyle(coral); Text(title).font(.system(size: 14, weight: .medium)); Text(detail).font(.system(size: 12)).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center) }.padding(20).frame(maxWidth: .infinity) }
}

struct OverviewView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(spacing: 12) {
            if let waiting = model.agents.sessions.first(where: { $0.state == "Needs you" }) {
                Button { model.agents.reveal(waiting) } label: {
                    Card { HStack { Image(systemName: "sparkles").foregroundStyle(.pink); VStack(alignment: .leading) { Text("\(waiting.provider) needs you").fontWeight(.semibold); Text(waiting.project).font(.caption).foregroundStyle(.white.opacity(0.7)) }; Spacer(); Image(systemName: "arrow.up.right") } }
                }.buttonStyle(.plain)
            }
            HStack(alignment: .top, spacing: 12) {
                QuotaCard(name: "Claude", snapshot: model.agents.claude, accent: coral, compact: true)
                QuotaCard(name: "Codex", snapshot: model.agents.codex, accent: lilac, compact: true)
            }
            Card {
                HStack(spacing: 13) {
                    Group { if let art = model.media.artwork { Image(nsImage: art).resizable().scaledToFill() } else { Image(systemName: "music.note").font(.title2).foregroundStyle(lilac) } }.frame(width: 46, height: 46).background(lilac.opacity(0.10)).clipShape(RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 4) { Text(model.media.title).font(.system(size: 13, weight: .medium)).lineLimit(1); Text(model.media.artist).font(.system(size: 11)).foregroundStyle(.white.opacity(0.7)).lineLimit(1) }
                    Spacer(minLength: 0)
                    Button { model.media.control("previous") } label: { Image(systemName: "backward.end.fill") }.help("Previous")
                    Button { model.media.control("toggle") } label: { Image(systemName: model.media.playing ? "pause.fill" : "play.fill") }.help("Play or pause")
                    Button { model.media.control("next") } label: { Image(systemName: "forward.end.fill") }.help("Next")
                }.buttonStyle(.plain).disabled(!model.media.available)
            }
            Card {
                VStack(spacing: 11) {
                    HStack { Image(systemName: model.power.charging ? "battery.100percent.bolt" : "battery.75percent").foregroundStyle(.green); Text(model.power.percent.map { "\($0)%" } ?? "No battery"); Spacer(); Text(model.power.time).foregroundStyle(.white.opacity(0.7)) }.font(.system(size: 11))
                    HStack { Button { model.audio.toggleMute() } label: { Image(systemName: model.audio.muted ? "speaker.slash" : "speaker.wave.2") }.buttonStyle(.plain).help("Mute"); Slider(value: Binding(get: { Double(model.audio.volume) }, set: { model.audio.set(Float($0)) })).tint(coral).disabled(!model.audio.available).accessibilityLabel("Volume"); Text("\(Int((model.audio.volume * 100).rounded()))%").monospacedDigit().font(.caption).frame(width: 32) }
                    if model.brightness.available { HStack { Image(systemName: "sun.max"); Slider(value: Binding(get: { Double(model.brightness.value) }, set: { model.brightness.set(Float($0)) })).tint(lilac).accessibilityLabel("Brightness") } }
                }
            }
            if let meeting = model.calendar.meetings.first { MeetingRow(meeting: meeting) }
            ForEach(model.downloads.downloads) { item in
                Card { VStack(alignment: .leading, spacing: 5) { Label(item.path, systemImage: "arrow.down.circle").lineLimit(1); Text("\(ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file)) received · \(ByteCountFormatter.string(fromByteCount: Int64(item.bytesPerSecond), countStyle: .file))/s").font(.caption).foregroundStyle(.white.opacity(0.7)); Text("Total size unavailable").font(.caption2).foregroundStyle(.white.opacity(0.7)) } }
            }
            ForEach(model.bluetooth.devices) { device in Card { VStack(alignment: .leading, spacing: 5) { Label(device.name, systemImage: "airpodspro"); Text(device.readings.isEmpty ? "Connected · Battery readings unavailable" : device.readings.joined(separator: " · ")).font(.caption).foregroundStyle(.white.opacity(0.7)) } } }
        }
    }
}

struct QuotaCard: View {
    var name: String; var snapshot: QuotaSnapshot?; var accent: Color; var compact = false
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack { Circle().fill(accent).frame(width: 7, height: 7); Text(name).font(.system(size: 12, weight: .semibold)); Spacer(); if snapshot?.stale == true { Image(systemName: "clock.badge.exclamationmark").foregroundStyle(.orange).help("Last update is over 10 minutes old") } }
                if let snapshot, !snapshot.windows.isEmpty {
                    ForEach(compact ? Array(snapshot.windows.prefix(2)) : snapshot.windows) { window in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .firstTextBaseline) { Text("\(Int(window.remaining.rounded()))%").font(.system(size: compact ? 23 : 25, weight: .medium, design: .rounded)); Text("left").font(.caption).foregroundStyle(.white.opacity(0.7)); Spacer() }
                            ProgressView(value: window.remaining, total: 100).tint(accent).accessibilityLabel("\(window.label), \(Int(window.used)) percent used")
                            HStack { Text(window.label); Spacer(); if let reset = window.reset { Text(reset, style: .time).help(reset.formatted()) } }.font(.system(size: 10)).foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    if !compact { HStack { Text(snapshot.plan ?? "Provider quota"); Spacer(); Text("Updated \(snapshot.receivedAt.formatted(date: .omitted, time: .shortened))") }.font(.caption2).foregroundStyle(.white.opacity(0.7)) }
                } else {
                    Text("—").font(.system(size: 29, weight: .light)).foregroundStyle(accent.opacity(0.5))
                    Text(snapshot == nil ? "Not connected" : "Quota unavailable").font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
                }
            }
        }
    }
}

struct AgentsView: View {
    @ObservedObject var service: AgentService
    var settings: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack { Text("YOUR USAGE").font(.system(size: 10, weight: .semibold)).tracking(1.5).foregroundStyle(.white.opacity(0.7)); Spacer(); Button("Refresh") { service.refresh() }.disabled(!service.connected); Button("Connect…", action: settings) }.font(.caption)
            QuotaCard(name: "Claude", snapshot: service.claude, accent: coral)
            QuotaCard(name: "Codex", snapshot: service.codex, accent: lilac)
            Text(service.status).font(.caption).foregroundStyle(.white.opacity(0.7))
            Text("SESSIONS").font(.system(size: 10, weight: .semibold)).tracking(1.5).foregroundStyle(.white.opacity(0.7)).padding(.top, 8)
            if service.sessions.isEmpty { EmptyCard(icon: "sparkles", title: "Ready when you are", detail: "Connect Claude hooks or a shared Codex server to receive session activity.") }
            ForEach(service.sessions) { session in
                Button { service.reveal(session) } label: {
                    Card { HStack { Circle().fill(session.state == "Needs you" ? .pink : .green).frame(width: 6, height: 6); VStack(alignment: .leading, spacing: 3) { Text(session.project).font(.system(size: 13, weight: .medium)); Text("\(session.provider) · \(session.state)").font(.caption).foregroundStyle(.white.opacity(0.7)) }; Spacer(); Text(session.timestamp, style: .relative).font(.caption2).foregroundStyle(.white.opacity(0.7)); Image(systemName: "arrow.up.right") } }
                }.buttonStyle(.plain)
            }
        }
    }
}

struct TrayView: View {
    @ObservedObject var service: TrayService
    @State private var selected = Set<UUID>()
    var body: some View {
        VStack(spacing: 12) {
            HStack { Text("\(service.items.count) \(service.items.count == 1 ? "file" : "files")").foregroundStyle(.white.opacity(0.7)); Spacer(); Button("Add…") { service.choose() }; Button(!selected.isEmpty && selected.count == service.items.count ? "Deselect" : "Select all") { selected = selected.count == service.items.count ? [] : Set(service.items.map(\.id)) } }.font(.caption)
            if service.items.isEmpty { EmptyCard(icon: "tray.and.arrow.down", title: "A place to put it", detail: "Drop files on the notch. Drag them back out, copy them, or send with AirDrop. Originals stay where they are.") }
            ForEach(service.items) { item in
                HStack(spacing: 12) {
                    Toggle("Select \(item.url.lastPathComponent)", isOn: Binding(get: { selected.contains(item.id) }, set: { if $0 { selected.insert(item.id) } else { selected.remove(item.id) } })).toggleStyle(.checkbox).labelsHidden()
                    Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path)).resizable().frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 3) { Text(item.url.lastPathComponent).font(.system(size: 12, weight: .medium)).lineLimit(1); Text(item.exists ? item.url.deletingLastPathComponent().lastPathComponent : "File moved or unavailable").font(.caption2).foregroundStyle(.white.opacity(0.7)) }
                    Spacer(); Button { NSWorkspace.shared.activateFileViewerSelecting([item.url]) } label: { Image(systemName: "arrow.up.right") }.buttonStyle(.plain).help("Reveal in Finder").disabled(!item.exists)
                }.padding(11).background(selected.contains(item.id) ? coral.opacity(0.09) : .white.opacity(0.04), in: RoundedRectangle(cornerRadius: 11))
                .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
            }
            if !selected.isEmpty { HStack { Button("Copy") { service.copy(selected) }; Button("AirDrop") { service.share(selected) }; Spacer(); Button("Remove from tray") { service.remove(selected); selected = [] } }.font(.caption) }
            if let error = service.error { Text(error).font(.caption).foregroundStyle(.orange) }
        }
    }
}

struct ClipboardView: View {
    @ObservedObject var service: ClipboardService
    var settings: () -> Void
    @State private var selected = Set<UUID>()
    @State private var search = ""
    private var filtered: [ClipItem] { service.items.filter { search.isEmpty || ($0.text ?? "Image").localizedCaseInsensitiveContains(search) } }
    var body: some View {
        VStack(spacing: 12) {
            if !service.enabled { EmptyCard(icon: "lock.shield", title: "Your clipboard, your choice", detail: service.error ?? "Enable encrypted history in Settings. Password managers and concealed clipboard items are excluded."); Button("Clipboard settings", action: settings) }
            else {
                TextField("Search clipboard", text: $search).textFieldStyle(.roundedBorder)
                HStack { Text("\(service.items.count) saved · encrypted").foregroundStyle(.white.opacity(0.7)); Spacer(); Button("Select all") { selected = Set(filtered.map(\.id)) }; if !selected.isEmpty { Button("Deselect") { selected = [] } } }.font(.caption)
                ForEach(filtered) { item in
                    HStack(spacing: 10) {
                        Toggle("Select clipboard item", isOn: Binding(get: { selected.contains(item.id) }, set: { if $0 { selected.insert(item.id) } else { selected.remove(item.id) } })).toggleStyle(.checkbox).labelsHidden()
                        if let data = item.image, let image = NSImage(data: data) { Image(nsImage: image).resizable().scaledToFit().frame(width: 50, height: 45) }
                        VStack(alignment: .leading, spacing: 4) { Text(item.text ?? "Image").font(.system(size: 12)).lineLimit(3); Text(item.created, style: .relative).font(.caption2).foregroundStyle(.white.opacity(0.7)) }
                        Spacer(minLength: 0)
                        Button { service.pin(item.id) } label: { Image(systemName: item.pinned ? "pin.fill" : "pin").foregroundStyle(item.pinned ? coral : .gray) }.buttonStyle(.plain).help(item.pinned ? "Unpin" : "Pin")
                    }.padding(12).background(selected.contains(item.id) ? coral.opacity(0.09) : .white.opacity(0.04), in: RoundedRectangle(cornerRadius: 11))
                    .onDrag { if let data = item.image, let image = NSImage(data: data) { return NSItemProvider(object: image) }; return NSItemProvider(object: (item.text ?? "") as NSString) }
                }
                if service.items.isEmpty { EmptyCard(icon: "doc.on.clipboard", title: "Nothing saved yet", detail: "Copy something in another app to start your history.") }
                if !selected.isEmpty { HStack { Button("Copy") { service.copy(selected) }; Button("AirDrop") { service.share(selected) }; Spacer(); Button("Delete saved items") { service.delete(selected); selected = [] } }.font(.caption) }
                if let error = service.error { Text(error).font(.caption).foregroundStyle(.orange) }
            }
        }
    }
}

struct MeetingRow: View {
    var meeting: Meeting
    var body: some View {
        Card { HStack { Image(systemName: "calendar").foregroundStyle(lilac); VStack(alignment: .leading, spacing: 4) { Text(meeting.title).font(.system(size: 13, weight: .medium)).lineLimit(1); TimelineView(.periodic(from: .now, by: 30)) { context in Text(meeting.start > context.date ? "Starts in \(max(1, Int(meeting.start.timeIntervalSince(context.date) / 60))) min" : "In progress").font(.caption).foregroundStyle(.white.opacity(0.7)) } }; Spacer(); if let url = meeting.link { Link("Join", destination: url).buttonStyle(.bordered) } } }
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
    var body: some View {
        TabView {
            Form {
                Section("Appearance") { Toggle("Glass appearance", isOn: $model.glass); Text("Liquid Glass on macOS 26 and later; native material on older systems. Respects Reduce Transparency and Increase Contrast.").font(.caption).foregroundStyle(.secondary); Toggle("Hide in full-screen apps", isOn: $model.hideFullScreen); Toggle("Keep the notch expanded", isOn: $model.pinned); Button("Show welcome tour") { model.onboarding = true; model.expanded = true } }
                Section("Startup") {
                    Toggle("Open Crest at login", isOn: $loginEnabled).onChange(of: loginEnabled) { _, value in
                        do { if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; loginError = "" } catch { loginError = error.localizedDescription; loginEnabled = SMAppService.mainApp.status == .enabled }
                    }
                    if !loginError.isEmpty { Text(loginError).foregroundStyle(.orange) }
                }
                Section("About Crest") { Text("Version 0.1.0 · Native Swift for macOS 14+"); Text("A local utility for agent activity, files and everyday controls.").foregroundStyle(.secondary); Text("Hover the notch to open. Pin it to keep it visible. Escape collapses it.").foregroundStyle(.secondary) }
            }.formStyle(.grouped).tabItem { Label("General", systemImage: "gearshape") }
            Form {
                Section("Codex") {
                    TextField("Executable", text: $codexPath)
                    TextField("Shared server socket (optional)", text: $codexSocket)
                    Text("Usage works through your existing Codex login. Session monitoring requires a shared server socket; a standalone connection cannot observe unrelated terminals.").font(.caption).foregroundStyle(.secondary)
                    HStack { Button("Connect / reconnect") { codexEnabled = true; model.agents.connect(path: codexPath, socket: codexSocket) }; Button("Disconnect") { codexEnabled = false; model.agents.disconnect() } }
                    Text(model.agents.status).font(.caption)
                }
                Section("Claude Code") {
                    Text("Install local event hooks and a usage status-line bridge. Existing hooks are preserved; an existing status-line command is forwarded. This does not approve agent actions.").font(.caption).foregroundStyle(.secondary)
                    HStack { Button("Install alerts + usage") { setup { try ClaudeSetup.install(includeStatus: true) } }; Button("Alerts only") { setup { try ClaudeSetup.install(includeStatus: false) } }; Button("Remove integration") { setup { try ClaudeSetup.uninstall() } } }
                    Text("Usage requires Claude Code 2.1.251+ and quota fields from the provider. No subscription credentials are read by Crest.").font(.caption).foregroundStyle(.secondary)
                    if !setupStatus.isEmpty { Text(setupStatus).font(.caption) }
                }
                Section("Calendar") { HStack { Button("Connect calendars") { Task { await model.calendar.connect() } }; Button("Disconnect") { model.calendar.disconnect() } }; Text(model.calendar.status).font(.caption); ForEach(model.calendar.meetings) { MeetingRow(meeting: $0) } }
            }.formStyle(.grouped).tabItem { Label("Connections", systemImage: "point.3.connected.trianglepath.dotted") }
            Form {
                Section("Encrypted clipboard") {
                    Toggle("Record clipboard history", isOn: Binding(get: { model.clipboard.enabled }, set: { model.clipboard.setEnabled($0) }))
                    Picker("Keep unpinned items", selection: Binding(get: { model.clipboard.days }, set: { model.clipboard.days = $0 })) { ForEach([1, 7, 30, 90, 365], id: \.self) { Text("\($0) days").tag($0) } }
                    Text("Pinned items remain until deleted. History is encrypted on this Mac. Password managers and concealed clipboard types are always excluded.").font(.caption).foregroundStyle(.secondary)
                    Text("Ignore apps (one bundle identifier per line)").font(.caption)
                    TextEditor(text: Binding(get: { model.clipboard.exclusions }, set: { model.clipboard.exclusions = $0 })).font(.system(.caption, design: .monospaced)).frame(height: 90)
                    if let error = model.clipboard.error { Text(error).font(.caption).foregroundStyle(.orange) }
                }
                Section("Screenshot imports") { HStack { Button("Choose screenshot folder…") { model.screenshots.choose(tray: model.tray, screenshots: true) }; Button("Stop") { model.screenshots.stop() } }; Text(model.screenshots.status).font(.caption) }
                Section("Downloads") { HStack { Button("Choose download folder…") { model.downloads.choose(tray: model.tray, screenshots: false) }; Button("Stop") { model.downloads.stop() } }; Text(model.downloads.status).font(.caption); Text("Shows partial-file size and growth speed. Browsers do not expose a universal download total; percentage and Safari package progress may be unavailable.").font(.caption).foregroundStyle(.secondary) }
            }.formStyle(.grouped).tabItem { Label("Files & Privacy", systemImage: "lock.shield") }
            Form {
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
                    Text("Requires Accessibility permission. Enable again after each launch. Only supported volume/brightness hardware events are intercepted; ordinary typing is not observed.").font(.caption).foregroundStyle(.secondary)
                    Text("Per-app battery drain is not available through the current adapter. Battery time is shown only when macOS provides an estimate.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Bluetooth") { Toggle("Monitor AirPods and battery devices", isOn: $bluetoothEnabled).onChange(of: bluetoothEnabled) { _, value in model.bluetooth.enable(value) }; Text(model.bluetooth.status).font(.caption) }
            }.formStyle(.grouped).tabItem { Label("Media & System", systemImage: "slider.horizontal.3") }
            Form {
                Section("Software updates") {
                    Text("Powered by Sparkle 2.10").font(.headline)
                    Text(model.updates.status).foregroundStyle(.secondary)
                    Toggle("Automatically check for updates", isOn: Binding(get: { model.updates.automatic }, set: { model.updates.automatic = $0 })).disabled(!model.updates.configured)
                    Toggle("Include beta releases", isOn: Binding(get: { model.updates.beta }, set: { model.updates.beta = $0 })).disabled(!model.updates.configured)
                    Button("Check for Updates…") { model.updates.check() }.disabled(!model.updates.configured)
                    Text("Release builds require our HTTPS feed, Sparkle public key and Apple Developer ID signing. There is no third-party app feed configured.").font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped).tabItem { Label("Updates", systemImage: "arrow.down.circle") }
        }.padding(12).frame(minWidth: 680, minHeight: 640)
    }
    private func setup(_ action: () throws -> String) { do { setupStatus = try action() } catch { setupStatus = error.localizedDescription } }
    private func configureMedia() { model.media.configure(enabled: mediaEnabled, player: mediaPlayer) }
}
