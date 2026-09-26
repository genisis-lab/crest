import SwiftUI
import AppKit
import UniformTypeIdentifiers
import QuickLook
import CrestCore

struct NotchView: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var collapse: Task<Void, Never>?
    @State private var dropping = false
    @State private var hovering = false
    private var waiting: AgentSession? { model.agents.sessions.first { $0.state == "Needs you" } }
    var body: some View {
        VStack(spacing: 0) {
            notchStrip
            if model.expanded {
                if model.onboarding { welcome }
                else {
                    toolbar
                    navigation
                    ScrollView {
                        VStack(spacing: 12) {
                            if let waiting {
                                Button { model.agents.reveal(waiting) } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "exclamationmark.bubble.fill").foregroundStyle(.pink)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("\(waiting.provider) needs your attention").font(.system(size: 12, weight: .semibold))
                                            Text(waiting.project).font(.caption).foregroundStyle(CrestStyle.secondary)
                                        }
                                        Spacer(); Image(systemName: "arrow.up.right")
                                    }.padding(12).background(.pink.opacity(0.10), in: RoundedRectangle(cornerRadius: 13))
                                }.buttonStyle(.plain).help("Return to the agent session")
                            }
                            switch model.tab {
                            case "Agents": AgentsView(service: model.agents, settings: { model.openSettings(.connections) })
                            case "Tray": TrayView(service: model.tray)
                            case "Clipboard": ClipboardView(service: model.clipboard, settings: { model.openSettings(.files) })
                            default: OverviewView(model: model)
                            }
                        }.padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 12)
                    }.scrollIndicators(.automatic)
                    footer
                }
            } else if let notice = model.notice {
                Label(notice, systemImage: waiting == nil ? "info.circle" : "exclamationmark.bubble.fill")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(waiting == nil ? .white : .pink)
                    .lineLimit(1).padding(.horizontal, 18).padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .modifier(NotchMaterial(enabled: model.glass && model.expanded, expanded: model.expanded))
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: model.expanded ? 28 : 14, bottomTrailingRadius: model.expanded ? 28 : 14))
        .overlay { if dropping { UnevenRoundedRectangle(bottomLeadingRadius: 28, bottomTrailingRadius: 28).stroke(CrestStyle.blue, lineWidth: 2).allowsHitTesting(false) } }
        .preferredColorScheme(.dark).environment(\.controlActiveState, .active)
        .tint(CrestStyle.blue)
        .onHover { inside in
            hovering = inside; collapse?.cancel()
            if inside { model.expanded = true }
            else { scheduleCollapse() }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropping) { providers in
            collapse?.cancel(); model.expanded = true; model.tab = "Tray"
            for provider in providers { provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url = (item as? URL) ?? (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                if let url { Task { @MainActor in model.tray.add([url]) } }
            } }
            return !providers.isEmpty
        }
        .onChange(of: dropping) { _, value in if value { collapse?.cancel(); model.expanded = true } else if !hovering { scheduleCollapse() } }
        .onChange(of: model.interacting) { _, value in if value { collapse?.cancel() } else if !hovering { scheduleCollapse() } }
        .onChange(of: model.pinned) { _, value in if value { collapse?.cancel() } else if !hovering { scheduleCollapse() } }
        .onExitCommand { model.pinned = false; model.expanded = false }
    }
    private func scheduleCollapse() {
        collapse?.cancel()
        guard !model.pinned && !model.onboarding && !model.interacting && !dropping else { return }
        collapse = Task {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled && !hovering && !model.pinned && !model.interacting && !dropping else { return }
            model.expanded = false
        }
    }
    private var notchStrip: some View {
        Button { model.expanded.toggle() } label: {
            HStack {
                Group {
                    if let art = model.media.artwork, model.media.playing { Image(nsImage: art).resizable().scaledToFill().clipShape(RoundedRectangle(cornerRadius: 4)) }
                    else { Image(systemName: waiting == nil ? "mountain.2.fill" : "exclamationmark.bubble.fill").foregroundStyle(waiting == nil ? .white.opacity(0.85) : .pink) }
                }.frame(width: 18, height: 18)
                Spacer(minLength: model.cutoutWidth)
                if model.media.playing {
                    Image(systemName: "waveform").foregroundStyle(CrestStyle.blue).symbolEffect(.variableColor.iterative, options: .repeating, isActive: !reduceMotion)
                } else if let percent = model.power.percent {
                    Text("\(percent)%").font(.system(size: 10, weight: .medium)).monospacedDigit().foregroundStyle(CrestStyle.secondary)
                }
            }.padding(.horizontal, 18).frame(height: model.notchHeight)
        }.buttonStyle(.plain).accessibilityLabel(model.expanded ? "Collapse Crest" : "Open Crest")
    }
    private var toolbar: some View {
        HStack(spacing: 8) {
            Text("Crest").font(.system(size: 15, weight: .semibold))
            Spacer()
            Button { model.pinned.toggle() } label: { Image(systemName: model.pinned ? "pin.fill" : "pin").frame(width: 14, height: 14) }
                .buttonStyle(QuietButtonStyle(selected: model.pinned)).help(model.pinned ? "Unpin Crest (⌘P)" : "Keep open (⌘P)").accessibilityLabel(model.pinned ? "Unpin Crest" : "Keep Crest open").keyboardShortcut("p")
            Button { model.openSettings(.general) } label: { Image(systemName: "gearshape").frame(width: 14, height: 14) }
                .buttonStyle(QuietButtonStyle()).help("Settings").accessibilityLabel("Settings")
            Button { model.pinned = false; model.expanded = false } label: { Image(systemName: "chevron.up").frame(width: 14, height: 14) }
                .buttonStyle(QuietButtonStyle()).help("Collapse (Escape)").accessibilityLabel("Collapse")
        }.padding(.horizontal, 19).padding(.top, 8).padding(.bottom, 12)
    }
    private var navigation: some View {
        HStack(spacing: 3) {
            ForEach(Array([("Overview", "square.grid.2x2"), ("Agents", "terminal"), ("Tray", "tray"), ("Clipboard", "doc.on.clipboard")].enumerated()), id: \.offset) { index, item in
                Button { model.tab = item.0 } label: {
                    HStack(spacing: 6) {
                        Image(systemName: item.1).font(.system(size: 11))
                        Text(item.0).font(.system(size: 12, weight: model.tab == item.0 ? .semibold : .medium))
                        if item.0 == "Tray", !model.tray.items.isEmpty { Text("\(model.tray.items.count)").font(.system(size: 9, weight: .semibold)).padding(.horizontal, 4).padding(.vertical, 2).background(.white.opacity(0.10), in: Capsule()) }
                    }.frame(maxWidth: .infinity).padding(.vertical, 7)
                        .background(model.tab == item.0 ? Color.white.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(model.tab == item.0 ? .white : CrestStyle.secondary)
                }.buttonStyle(.plain).keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
                    .accessibilityAddTraits(model.tab == item.0 ? .isSelected : []).help("\(item.0) (⌘\(index + 1))")
            }
        }.padding(3).background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 11)).padding(.horizontal, 16)
    }
    private var footer: some View {
        HStack(spacing: 5) {
            Image(systemName: model.notice == nil ? "lock" : "checkmark.circle").font(.system(size: 9))
            Text(model.notice ?? "On your Mac").lineLimit(1)
            Spacer()
            Text(model.pinned ? "Pinned" : "Hover to keep open")
        }.font(.system(size: 10)).foregroundStyle(CrestStyle.tertiary).padding(.horizontal, 20).padding(.vertical, 11)
    }
    private var welcome: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "mountain.2.fill").font(.system(size: 32)).foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 8) {
                Text("Welcome to Crest").font(.system(size: 25, weight: .semibold))
                Text("A quiet place for the things you reach for.").font(.system(size: 13)).foregroundStyle(CrestStyle.secondary)
            }
            VStack(alignment: .leading, spacing: 18) {
                welcomeRow("cursorarrow", "Always within reach", "Hover to open. Pin to keep it here.")
                welcomeRow("terminal", "Stay with your work", "See agent usage and return to sessions that need you.")
                welcomeRow("tray", "A place between apps", "Drop files here, then copy, preview, or AirDrop.")
            }
            Spacer(minLength: 0)
            Text("Clipboard history and calendars are off until you choose to connect them.").font(.caption).foregroundStyle(CrestStyle.secondary)
            HStack { Button("Continue") { model.finishOnboarding() }.buttonStyle(.borderedProminent); Button("Set up connections…") { model.finishOnboarding(); model.openSettings(.connections) }.buttonStyle(.borderless) }
        }.padding(28)
    }
    private func welcomeRow(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 14) { Image(systemName: icon).font(.system(size: 19)).frame(width: 28).foregroundStyle(CrestStyle.blue); VStack(alignment: .leading, spacing: 3) { Text(title).font(.system(size: 12, weight: .semibold)); Text(detail).font(.system(size: 12)).foregroundStyle(CrestStyle.secondary) } }
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        content.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(scheme == .dark ? Color.white.opacity(0.055) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(scheme == .dark ? .white.opacity(contrast == .increased ? 0.55 : 0.07) : .black.opacity(0.08), lineWidth: 0.5))
    }
}
struct EmptyCard: View {
    var icon: String; var title: String; var detail: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 30, weight: .light)).foregroundStyle(CrestStyle.secondary).frame(height: 42)
            Text(title).font(.system(size: 14, weight: .semibold))
            Text(detail).font(.system(size: 12)).foregroundStyle(CrestStyle.secondary).multilineTextAlignment(.center).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        }.padding(24).frame(maxWidth: .infinity)
    }
}

struct OverviewView: View {
    @ObservedObject var model: AppModel
    @AppStorage("showMedia") private var showMedia = true
    @AppStorage("showUsage") private var showUsage = true
    @AppStorage("showSystem") private var showSystem = true
    var body: some View {
        VStack(spacing: 12) {
            if showMedia || showSystem {
                HStack(alignment: .top, spacing: 12) {
                    if showMedia { MediaCard(service: model.media, settings: { model.openSettings(.media) }).frame(maxWidth: .infinity) }
                    if showSystem { systemCard.frame(maxWidth: .infinity) }
                }
            }
            if showUsage {
                HStack(alignment: .top, spacing: 12) {
                    QuotaCard(name: "Claude", snapshot: model.agents.claude, connected: model.agents.claude != nil, compact: true, connect: { model.openSettings(.connections) })
                    QuotaCard(name: "Codex", snapshot: model.agents.codex, connected: model.agents.connected, compact: true, connect: { model.openSettings(.connections) })
                }
            }
            if let meeting = model.calendar.meetings.first { MeetingRow(meeting: meeting) }
            ForEach(model.downloads.downloads) { item in
                Card {
                    HStack { Image(systemName: "arrow.down.circle.fill").foregroundStyle(CrestStyle.blue); VStack(alignment: .leading, spacing: 4) { Text(item.path).font(.system(size: 12, weight: .medium)).lineLimit(1); Text("\(ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file)) received · \(ByteCountFormatter.string(fromByteCount: Int64(item.bytesPerSecond), countStyle: .file))/s").font(.caption).foregroundStyle(CrestStyle.secondary) }; Spacer(); ProgressView().controlSize(.small) }
                }
            }
            ForEach(model.bluetooth.devices) { device in Card { Label { VStack(alignment: .leading, spacing: 3) { Text(device.name).font(.system(size: 12, weight: .medium)); Text(device.readings.isEmpty ? "Connected · Battery unavailable" : device.readings.joined(separator: " · ")).font(.caption).foregroundStyle(CrestStyle.secondary) } } icon: { Image(systemName: "airpodspro").font(.title2) } } }
            if !showMedia && !showSystem && !showUsage { EmptyCard(icon: "slider.horizontal.3", title: "Make room for what matters", detail: "Choose the controls you want to see in Settings."); Button("Customize Overview…") { model.openSettings(.general) }.buttonStyle(.bordered) }
        }
    }
    private var systemCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack { Label(model.power.percent.map { "\($0)%" } ?? "Power", systemImage: model.power.charging ? "battery.100percent.bolt" : "battery.75percent").font(.system(size: 12, weight: .semibold)); Spacer(); Text(model.power.charging ? "Connected" : "Battery").font(.system(size: 10)).foregroundStyle(CrestStyle.secondary) }
                HStack(spacing: 9) { Button { model.audio.toggleMute() } label: { Image(systemName: model.audio.muted ? "speaker.slash.fill" : "speaker.wave.2.fill").frame(width: 18) }.buttonStyle(.plain).disabled(!model.audio.available).accessibilityLabel("Mute sound"); Slider(value: Binding(get: { Double(model.audio.volume) }, set: { model.audio.set(Float($0)) })).tint(.white).disabled(!model.audio.available).accessibilityLabel("Volume"); Text(model.audio.available ? "\(Int((model.audio.volume * 100).rounded()))" : "—").font(.system(size: 10)).monospacedDigit().frame(width: 22) }
                if model.brightness.available { HStack(spacing: 9) { Image(systemName: "sun.max.fill").frame(width: 18); Slider(value: Binding(get: { Double(model.brightness.value) }, set: { model.brightness.set(Float($0)) })).tint(.white).accessibilityLabel("Brightness"); Text("\(Int((model.brightness.value * 100).rounded()))").font(.system(size: 10)).monospacedDigit().frame(width: 22) } }
                else { Text(model.power.time).font(.system(size: 11)).foregroundStyle(CrestStyle.secondary).lineLimit(2) }
            }.frame(height: 108, alignment: .top)
        }
    }
}
struct MediaCard: View {
    @ObservedObject var service: MediaService
    var settings: () -> Void
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Group { if let art = service.artwork { Image(nsImage: art).resizable().scaledToFill() } else { Image(systemName: "music.note").font(.system(size: 20)).foregroundStyle(CrestStyle.secondary) } }
                        .frame(width: 44, height: 44).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10)).clipShape(RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 4) { Text(service.available ? service.title : "Now Playing").font(.system(size: 12, weight: .semibold)).lineLimit(2); Text(service.available ? service.artist : "Music, at your fingertips").font(.system(size: 11)).foregroundStyle(CrestStyle.secondary).lineLimit(1) }
                }
                if service.available {
                    HStack(spacing: 25) {
                        Spacer(minLength: 0)
                        Button { service.control("previous") } label: { Image(systemName: "backward.fill") }.accessibilityLabel("Previous track")
                        Button { service.control("toggle") } label: { Image(systemName: service.playing ? "pause.fill" : "play.fill").font(.system(size: 21)) }.accessibilityLabel(service.playing ? "Pause" : "Play")
                        Button { service.control("next") } label: { Image(systemName: "forward.fill") }.accessibilityLabel("Next track")
                        Spacer(minLength: 0)
                    }.buttonStyle(.plain).frame(height: 34)
                } else {
                    Button("Choose a player…", action: settings).buttonStyle(.bordered).controlSize(.small).padding(.top, 4)
                }
            }.frame(height: 108, alignment: .top)
        }
    }
}

struct QuotaCard: View {
    var name: String; var snapshot: QuotaSnapshot?; var connected: Bool; var compact = false; var connect: () -> Void
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 7) {
                        Image(systemName: name == "Claude" ? "sparkle" : "terminal").foregroundStyle(name == "Claude" ? Color.orange.opacity(0.85) : CrestStyle.blue)
                        Text(name).font(.system(size: 12, weight: .semibold))
                        Spacer()
                        if let snapshot, snapshot.isStale(at: context.date) || !connected { Image(systemName: "clock.badge.exclamationmark").foregroundStyle(.orange).help("Showing previously received usage") }
                        else if !compact, let plan = snapshot?.plan { Text(plan.capitalized).font(.caption).foregroundStyle(CrestStyle.secondary) }
                    }
                    if let snapshot, !snapshot.windows.isEmpty {
                        ForEach(compact ? Array(snapshot.windows.prefix(2)) : snapshot.windows) { window in
                            VStack(spacing: 5) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(window.label).font(.system(size: 11)).foregroundStyle(CrestStyle.secondary).lineLimit(1)
                                    Spacer(minLength: 4)
                                    Text("\(window.remaining.formatted(.number.precision(.fractionLength(0))))% left").font(.system(size: 11, weight: .semibold)).monospacedDigit()
                                }
                                GeometryReader { proxy in
                                    Capsule().fill(.white.opacity(0.09)).overlay(alignment: .leading) { Capsule().fill(window.remaining <= 10 ? Color.orange : CrestStyle.blue.opacity(0.85)).frame(width: max(0, proxy.size.width * min(100, window.remaining) / 100)) }
                                }.frame(height: 4).accessibilityLabel("\(window.label), \(window.remaining.formatted()) percent remaining")
                                if !compact, let reset = window.reset { Text(reset <= context.date ? "Reset passed · refresh to update" : "Resets \(reset.formatted(date: .abbreviated, time: .shortened))").font(.system(size: 10)).foregroundStyle(CrestStyle.secondary).frame(maxWidth: .infinity, alignment: .leading) }
                            }
                        }
                        if !compact { Text("Updated \(snapshot.receivedAt.formatted(date: .abbreviated, time: .shortened))").font(.system(size: 10)).foregroundStyle(CrestStyle.tertiary) }
                        else if snapshot.windows.count > 2 { Text("+\(snapshot.windows.count - 2) more in Agents").font(.system(size: 10)).foregroundStyle(CrestStyle.secondary) }
                    } else {
                        Text(connected ? "No usage returned" : "Not connected").font(.system(size: 11)).foregroundStyle(CrestStyle.secondary)
                        Button("Set up…", action: connect).buttonStyle(.borderless).font(.system(size: 11))
                    }
                }.frame(minHeight: compact ? 97 : 0, alignment: .top)
            }
        }
    }
}
struct AgentsView: View {
    @ObservedObject var service: AgentService
    var settings: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Label(service.connected ? "Codex connected" : "Connections", systemImage: service.connected ? "checkmark.circle" : "point.3.connected.trianglepath.dotted").font(.system(size: 11)).foregroundStyle(CrestStyle.secondary)
                Spacer(); Button("Refresh") { service.refresh() }.disabled(!service.connected || service.refreshing); Button("Manage…", action: settings)
            }.font(.caption).controlSize(.small)
            QuotaCard(name: "Claude", snapshot: service.claude, connected: service.claude != nil, connect: settings)
            QuotaCard(name: "Codex", snapshot: service.codex, connected: service.connected, connect: settings)
            Text(service.status).font(.system(size: 11)).foregroundStyle(CrestStyle.secondary).frame(maxWidth: .infinity, alignment: .leading)
            HStack { Text("Sessions").font(.system(size: 12, weight: .semibold)); Spacer(); Text("\(service.sessions.count)").font(.caption).foregroundStyle(CrestStyle.secondary) }.padding(.top, 4)
            if service.sessions.isEmpty { EmptyCard(icon: "terminal", title: "No active sessions", detail: "Connect Claude hooks or a shared Codex server to see activity and requests here.") }
            ForEach(service.sessions) { session in
                Button { service.reveal(session) } label: {
                    Card { HStack(spacing: 10) { Image(systemName: session.state == "Needs you" ? "exclamationmark.bubble.fill" : session.state == "Working" ? "ellipsis.circle" : "checkmark.circle").foregroundStyle(session.state == "Needs you" ? .pink : CrestStyle.secondary); VStack(alignment: .leading, spacing: 3) { Text(session.project).font(.system(size: 12, weight: .semibold)); Text("\(session.provider) · \(session.state)").font(.system(size: 11)).foregroundStyle(CrestStyle.secondary) }; Spacer(); Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(CrestStyle.secondary) } }
                }.buttonStyle(.plain)
            }
        }
    }
}

struct TrayView: View {
    @ObservedObject var service: TrayService
    @State private var selected = Set<UUID>()
    @State private var search = ""
    @State private var preview: URL?
    private var filtered: [TrayItem] { service.items.filter { search.isEmpty || $0.url.lastPathComponent.localizedCaseInsensitiveContains(search) } }
    var body: some View {
        VStack(spacing: 12) {
            HStack { Label("\(service.items.count) \(service.items.count == 1 ? "item" : "items")", systemImage: "tray").foregroundStyle(CrestStyle.secondary); Spacer(); if service.canUndo { Button("Undo removal") { service.undoRemoval() } }; Button { service.choose() } label: { Label("Add", systemImage: "plus") } }.font(.caption).controlSize(.small)
            if !service.items.isEmpty { TextField("Search files", text: $search).textFieldStyle(.roundedBorder).accessibilityLabel("Search files") }
            if service.items.isEmpty { EmptyCard(icon: "tray.and.arrow.down", title: "Drop something here", detail: "Keep files within reach as you move between apps. Your originals stay where they are."); Button("Choose files…") { service.choose() }.buttonStyle(.bordered) }
            else if filtered.isEmpty { EmptyCard(icon: "magnifyingglass", title: "No matching files", detail: "Try another name.") }
            ForEach(filtered) { item in
                HStack(spacing: 10) {
                    Toggle("Select \(item.url.lastPathComponent)", isOn: selection(item.id)).toggleStyle(.checkbox).labelsHidden()
                    Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path)).resizable().frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 3) { Text(item.url.lastPathComponent).font(.system(size: 12, weight: .medium)).lineLimit(1); Text(item.exists ? item.url.deletingLastPathComponent().lastPathComponent : "File unavailable").font(.system(size: 10)).foregroundStyle(item.exists ? CrestStyle.secondary : .orange) }
                    Spacer(minLength: 0)
                    Button { preview = item.url } label: { Image(systemName: "eye") }.help("Quick Look").accessibilityLabel("Preview \(item.url.lastPathComponent)").disabled(!item.exists)
                    Button { NSWorkspace.shared.activateFileViewerSelecting([item.url]) } label: { Image(systemName: "arrow.up.right") }.help("Reveal in Finder").accessibilityLabel("Reveal \(item.url.lastPathComponent) in Finder").disabled(!item.exists)
                }.buttonStyle(.plain).padding(11).background(.white.opacity(selected.contains(item.id) ? 0.10 : 0.04), in: RoundedRectangle(cornerRadius: 12))
                .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
            }
            if !service.items.isEmpty {
                HStack { Button(selected.isEmpty ? "Select all" : "Deselect") { selected = selected.isEmpty ? Set(filtered.map(\.id)) : [] }; Spacer(); if !selected.isEmpty { Button("Copy") { service.copy(selected) }; Button("AirDrop") { service.share(selected) }; Button("Remove") { service.remove(selected); selected = [] }.help("Remove references; keep original files") } }.font(.caption).controlSize(.small)
            }
            if let feedback = service.feedback { Label(feedback, systemImage: "checkmark.circle").font(.caption).foregroundStyle(CrestStyle.secondary) }
            if let error = service.error { Text(error).font(.caption).foregroundStyle(.orange) }
        }.quickLookPreview($preview)
        .onChange(of: search) { _, _ in selected = [] }
        .onChange(of: preview) { _, value in service.onInteraction?(value != nil) }
        .onDisappear { service.onInteraction?(false) }
        .onChange(of: service.items.map(\.id)) { _, ids in selected.formIntersection(ids) }
    }
    private func selection(_ id: UUID) -> Binding<Bool> { Binding(get: { selected.contains(id) }, set: { if $0 { selected.insert(id) } else { selected.remove(id) } }) }
}
struct ClipboardView: View {
    @ObservedObject var service: ClipboardService
    var settings: () -> Void
    @State private var selected = Set<UUID>()
    @State private var search = ""
    private var filtered: [ClipItem] { service.items.filter { search.isEmpty || ($0.text ?? "Image").localizedCaseInsensitiveContains(search) }.sorted { $0.pinned != $1.pinned ? $0.pinned : $0.created > $1.created } }
    var body: some View {
        VStack(spacing: 12) {
            if !service.enabled { EmptyCard(icon: "lock.shield", title: "Your clipboard. Your choice.", detail: service.error ?? "Keep an encrypted history of text and images on this Mac. Password managers and concealed items are excluded."); Button("Set up clipboard history…", action: settings).buttonStyle(.bordered) }
            else {
                TextField("Search clipboard", text: $search).textFieldStyle(.roundedBorder)
                HStack { Label("\(service.items.count) saved", systemImage: "lock").foregroundStyle(CrestStyle.secondary); Spacer(); Button(selected.isEmpty ? "Select all" : "Deselect") { selected = selected.isEmpty ? Set(filtered.map(\.id)) : [] } }.font(.caption)
                ForEach(filtered) { item in
                    HStack(spacing: 10) {
                        Toggle("Select clipboard item", isOn: Binding(get: { selected.contains(item.id) }, set: { if $0 { selected.insert(item.id) } else { selected.remove(item.id) } })).toggleStyle(.checkbox).labelsHidden()
                        if let data = item.image, let image = NSImage(data: data) { Image(nsImage: image).resizable().scaledToFit().frame(width: 42, height: 42) }
                        VStack(alignment: .leading, spacing: 4) { Text(item.text ?? "Image").font(.system(size: 12)).lineLimit(3); Text(item.created, style: .relative).font(.system(size: 10)).foregroundStyle(CrestStyle.secondary) }
                        Spacer(minLength: 0)
                        Button { service.pin(item.id) } label: { Image(systemName: item.pinned ? "pin.fill" : "pin").foregroundStyle(item.pinned ? CrestStyle.blue : CrestStyle.secondary) }.buttonStyle(.plain).help(item.pinned ? "Unpin" : "Pin").accessibilityLabel(item.pinned ? "Unpin item" : "Pin item")
                    }.padding(12).background(.white.opacity(selected.contains(item.id) ? 0.10 : 0.04), in: RoundedRectangle(cornerRadius: 12))
                    .onDrag { if let data = item.image, let image = NSImage(data: data) { return NSItemProvider(object: image) }; return NSItemProvider(object: (item.text ?? "") as NSString) }
                }
                if filtered.isEmpty { EmptyCard(icon: search.isEmpty ? "doc.on.clipboard" : "magnifyingglass", title: search.isEmpty ? "Nothing saved yet" : "No matches", detail: search.isEmpty ? "Copy something in another app to start your history." : "Try another search.") }
                if !selected.isEmpty { HStack { Button("Copy") { service.copy(selected) }; Button("AirDrop") { service.share(selected) }; Spacer(); Button("Delete saved items") { service.delete(selected); selected = [] } }.font(.caption).controlSize(.small) }
                if let feedback = service.feedback { Text(feedback).font(.caption).foregroundStyle(CrestStyle.secondary) }
                if let error = service.error { Text(error).font(.caption).foregroundStyle(.orange) }
            }
        }.onChange(of: search) { _, _ in selected = [] }.onChange(of: service.items.map(\.id)) { _, ids in selected.formIntersection(ids) }
    }
}
struct MeetingRow: View {
    var meeting: Meeting
    var body: some View {
        Card { HStack(spacing: 12) { Image(systemName: "calendar").font(.system(size: 20)).foregroundStyle(.red.opacity(0.85)); VStack(alignment: .leading, spacing: 4) { Text(meeting.title).font(.system(size: 12, weight: .semibold)).lineLimit(1); TimelineView(.periodic(from: .now, by: 30)) { context in Text(meeting.start > context.date ? "In \(max(1, Int(meeting.start.timeIntervalSince(context.date) / 60))) min · \(meeting.start.formatted(date: .omitted, time: .shortened))" : "In progress").font(.system(size: 11)).foregroundStyle(.secondary) } }; Spacer(); if let url = meeting.link { Link("Join", destination: url).buttonStyle(.bordered).controlSize(.small) } } }
    }
}
