import SwiftUI
import AppKit
import UniformTypeIdentifiers
import QuickLook
import CrestCore

struct NotchView: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("hoverOpen") private var hoverOpen = HoverOpen.short.rawValue
    @AppStorage("haptics") private var haptics = true
    @AppStorage("showBatteryPercent") private var showBattery = true
    @Namespace private var tabs
    @State private var collapse: Task<Void, Never>?
    @State private var opening: Task<Void, Never>?
    @State private var dropping = false
    @State private var hovering = false
    private var waiting: AgentSession? { model.agents.sessions.first { $0.state == "Needs you" } }
    private var radius: CGFloat { model.expanded ? 28 : 14 }
    var body: some View {
        VStack(spacing: 0) {
            notchStrip
            if model.expanded {
                Group {
                    if model.onboarding { welcome }
                    else {
                        header
                        ScrollView {
                            VStack(spacing: 12) {
                                if let waiting {
                                    Button { model.agents.reveal(waiting) } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: "exclamationmark.bubble.fill").foregroundStyle(.pink)
                                                .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text("\(waiting.provider) needs your attention").font(.system(size: 12, weight: .semibold))
                                                Text(waiting.project).font(.caption).foregroundStyle(CrestStyle.secondary)
                                            }
                                            Spacer(); Image(systemName: "arrow.up.right")
                                        }.padding(12).background(.pink.opacity(0.10), in: RoundedRectangle(cornerRadius: 13))
                                    }.buttonStyle(.plain).help("Return to the agent session")
                                }
                                switch model.tab {
                                case .agents: AgentsView(service: model.agents, settings: { model.openSettings(.connections) })
                                case .tray: TrayView(service: model.tray)
                                case .clipboard: ClipboardView(service: model.clipboard, settings: { model.openSettings(.files) })
                                case .notes: NotesView(service: model.notes, editing: $model.editing)
                                case .overview: OverviewView(model: model)
                                }
                            }.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 12)
                        }.scrollIndicators(.automatic)
                        footer
                    }
                }
                .transition(reduceMotion ? AnyTransition.opacity : AnyTransition.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            } else if let notice = model.notice {
                NoticeView(notice: notice).padding(.horizontal, 18).padding(.bottom, 10)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(reduceMotion ? nil : .smooth(duration: 0.26), value: model.expanded)
        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: model.notice)
        .modifier(NotchMaterial(enabled: model.glass && model.expanded, expanded: model.expanded))
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius))
        .overlay {
            if dropping {
                ZStack {
                    UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius).stroke(CrestStyle.blue, lineWidth: 2)
                    if model.expanded {
                        VStack(spacing: 8) {
                            Image(systemName: "tray.and.arrow.down.fill").font(.system(size: 28))
                            Text("Drop to add to Tray").font(.system(size: 13, weight: .semibold))
                            Text("Originals stay where they are").font(.system(size: 11)).foregroundStyle(CrestStyle.secondary)
                        }
                        .foregroundStyle(CrestStyle.blue).padding(.horizontal, 28).padding(.vertical, 20)
                        .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 18))
                    }
                }.allowsHitTesting(false)
            }
        }
        .preferredColorScheme(.dark).environment(\.controlActiveState, .active)
        .tint(CrestStyle.blue)
        .onHover { inside in
            hovering = inside; collapse?.cancel(); opening?.cancel()
            if inside {
                if model.expanded { model.keyboardOpen = false } else { scheduleOpen() }
            } else { scheduleCollapse() }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropping) { providers in
            collapse?.cancel(); model.expanded = true; model.tab = .tray
            for provider in providers { provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url = (item as? URL) ?? (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                if let url { Task { @MainActor in model.tray.add([url]) } }
            } }
            return !providers.isEmpty
        }
        .onChange(of: dropping) { _, value in if value { collapse?.cancel(); model.expanded = true } else if !hovering { scheduleCollapse() } }
        .onChange(of: model.interacting) { _, value in if value { collapse?.cancel() } else if !hovering { scheduleCollapse() } }
        .onChange(of: model.editing) { _, value in if value { collapse?.cancel() } else if !hovering { scheduleCollapse() } }
        .onChange(of: model.pinned) { _, value in if value { collapse?.cancel() } else if !hovering { scheduleCollapse() } }
        .onChange(of: model.expanded) { _, value in if !value { model.editing = false } }
        .onExitCommand { model.pinned = false; model.keyboardOpen = false; model.editing = false; model.expanded = false }
    }
    private func scheduleOpen() {
        guard let delay = (HoverOpen(rawValue: hoverOpen) ?? .short).delay else { return }
        opening = Task {
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled, hovering, !model.expanded else { return }
            model.keyboardOpen = false; model.expanded = true
            if haptics { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
        }
    }
    private func scheduleCollapse() {
        collapse?.cancel()
        guard !model.pinned && !model.keyboardOpen && !model.onboarding && !model.interacting && !model.editing && !dropping else { return }
        collapse = Task {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled && !hovering && !model.pinned && !model.keyboardOpen && !model.interacting && !model.editing && !dropping else { return }
            model.expanded = false
        }
    }

    // MARK: Collapsed notch

    private var notchStrip: some View {
        Button { opening?.cancel(); model.expanded.toggle() } label: {
            HStack(spacing: 0) {
                leadingEdge.frame(minWidth: 18, alignment: .leading)
                Spacer(minLength: model.cutoutWidth)
                trailingEdge.frame(minWidth: 18, alignment: .trailing)
            }
            .padding(.horizontal, 16).frame(height: model.notchHeight)
            .contentShape(Rectangle())
            .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: model.liveActivity)
        }.buttonStyle(.plain).accessibilityLabel(model.expanded ? "Collapse Crest" : "Open Crest")
    }
    @ViewBuilder private var leadingEdge: some View {
        switch model.liveActivity {
        case .attention:
            Image(systemName: "exclamationmark.bubble.fill").foregroundStyle(.pink)
                .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
        case .timer:
            TimelineView(.periodic(from: .now, by: 1)) { context in
                ProgressRing(progress: model.focus.timer.progress(at: context.date), tint: .orange) {
                    Image(systemName: model.focus.timer.isPaused ? "pause.fill" : "timer").font(.system(size: 8, weight: .bold))
                }
            }
        case .meeting:
            Image(systemName: "calendar").foregroundStyle(Color.red.opacity(0.9))
        case .download:
            ProgressRing(progress: model.downloads.downloads.first?.fraction, tint: CrestStyle.blue) {
                Image(systemName: "arrow.down").font(.system(size: 8, weight: .bold))
            }
        case .media, nil:
            if let art = model.media.artwork, model.media.playing {
                Image(nsImage: art).resizable().scaledToFill().frame(width: 18, height: 18).clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(systemName: "mountain.2.fill").foregroundStyle(.white.opacity(0.85))
            }
        }
    }
    @ViewBuilder private var trailingEdge: some View {
        switch model.liveActivity {
        case .attention(let provider):
            Text(provider).font(.system(size: 11, weight: .semibold)).foregroundStyle(.pink).lineLimit(1)
        case .timer:
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(TimeFormat.string(model.focus.timer.remaining(at: context.date), roundingUp: true))
                    .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(model.focus.timer.isPaused ? CrestStyle.secondary : .orange)
            }
        case .meeting:
            if let meeting = model.upcomingMeeting() {
                TimelineView(.periodic(from: .now, by: 15)) { context in
                    Text(meeting.start > context.date ? "in " + TimeFormat.compact(meeting.start.timeIntervalSince(context.date)) : "Now")
                        .font(.system(size: 11, weight: .semibold)).monospacedDigit().foregroundStyle(Color.red.opacity(0.9))
                }
            }
        case .download:
            if let item = model.downloads.downloads.first {
                Text(downloadSummary(item))
                    .font(.system(size: 10, weight: .semibold)).monospacedDigit().foregroundStyle(CrestStyle.blue).lineLimit(1)
            }
        case .media:
            Image(systemName: "waveform").foregroundStyle(CrestStyle.blue).symbolEffect(.variableColor.iterative, options: .repeating, isActive: !reduceMotion)
        case nil:
            HStack(spacing: 3) {
                if model.awake.active { Image(systemName: "cup.and.saucer.fill").font(.system(size: 9)).foregroundStyle(.orange) }
                if showBattery, let percent = model.power.percent {
                    if model.power.charging { Image(systemName: "bolt.fill").font(.system(size: 8)).foregroundStyle(.green) }
                    Text("\(percent)%").font(.system(size: 10, weight: .medium)).monospacedDigit()
                        .foregroundStyle(percent <= 20 && !model.power.charging ? Color.red : CrestStyle.secondary)
                }
            }
        }
    }

    private func downloadSummary(_ item: DownloadActivity) -> String {
        if let fraction = item.fraction { return "\(Int(fraction * 100))%" }
        return ByteCountFormatter.string(fromByteCount: Int64(item.bytesPerSecond), countStyle: .file) + "/s"
    }

    // MARK: Expanded chrome

    private var header: some View {
        HStack(spacing: 6) {
            HStack(spacing: 2) {
                ForEach(Array(NotchTab.allCases.enumerated()), id: \.offset) { index, tab in tabButton(tab, index: index) }
            }.padding(3).background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 11))
            Spacer(minLength: 4)
            Button { model.pinned.toggle() } label: { Image(systemName: model.pinned ? "pin.fill" : "pin").frame(width: 14, height: 14) }
                .buttonStyle(QuietButtonStyle(selected: model.pinned)).help(model.pinned ? "Unpin Crest (⌘P)" : "Keep open (⌘P)").accessibilityLabel(model.pinned ? "Unpin Crest" : "Keep Crest open").keyboardShortcut("p")
            Button { model.openSettings(.general) } label: { Image(systemName: "gearshape").frame(width: 14, height: 14) }
                .buttonStyle(QuietButtonStyle()).help("Settings").accessibilityLabel("Settings")
            Button { model.pinned = false; model.keyboardOpen = false; model.editing = false; model.expanded = false } label: { Image(systemName: "chevron.up").frame(width: 14, height: 14) }
                .buttonStyle(QuietButtonStyle()).help("Collapse (Escape)").accessibilityLabel("Collapse")
        }.padding(.horizontal, 14).padding(.top, 2).padding(.bottom, 12)
    }
    private func tabButton(_ tab: NotchTab, index: Int) -> some View {
        let selected = model.tab == tab
        return Button { withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) { model.tab = tab } } label: {
            HStack(spacing: 5) {
                Image(systemName: tab.symbol).font(.system(size: 11, weight: .medium))
                Text(tab.rawValue).font(.system(size: 11.5, weight: selected ? .semibold : .medium))
                if let badge = badge(for: tab) {
                    Text(badge.0).font(.system(size: 9, weight: .bold)).monospacedDigit()
                        .padding(.horizontal, 4).padding(.vertical, 1.5).background(badge.1, in: Capsule())
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .foregroundStyle(selected ? .white : CrestStyle.secondary)
            .background {
                if selected { RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.13)).matchedGeometryEffect(id: "selection", in: tabs) }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain).fixedSize()
        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
        .accessibilityAddTraits(selected ? .isSelected : []).help("\(tab.rawValue) (⌘\(index + 1))")
    }
    private func badge(for tab: NotchTab) -> (String, Color)? {
        switch tab {
        case .agents:
            let count = model.agents.sessions.filter { $0.state == "Needs you" }.count
            return count > 0 ? ("\(count)", Color.pink.opacity(0.45)) : nil
        case .tray: return model.tray.items.isEmpty ? nil : ("\(model.tray.items.count)", Color.white.opacity(0.12))
        default: return nil
        }
    }
    private var footer: some View {
        HStack(spacing: 5) {
            Image(systemName: model.notice?.symbol ?? "lock").font(.system(size: 9))
            Text(model.notice?.text ?? "On your Mac").lineLimit(1)
            Spacer()
            if model.awake.active { Label("Awake", systemImage: "cup.and.saucer.fill").foregroundStyle(.orange.opacity(0.8)).help("Crest is keeping this Mac awake") }
            Text(model.pinned ? "Pinned" : model.keyboardOpen ? "Escape to close" : "Hover to keep open")
        }.font(.system(size: 10)).foregroundStyle(CrestStyle.tertiary).padding(.horizontal, 20).padding(.vertical, 11)
    }
    private var welcome: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "mountain.2.fill").font(.system(size: 30)).foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 8) {
                Text("Welcome to Crest").font(.system(size: 25, weight: .semibold))
                Text("A quiet place for the things you reach for.").font(.system(size: 13)).foregroundStyle(CrestStyle.secondary)
            }
            VStack(alignment: .leading, spacing: 14) {
                welcomeRow("cursorarrow", "Always within reach", "Hover to open. Pin to keep it here. Timers, meetings and agents appear beside the notch.")
                welcomeRow("terminal", "Stay with your work", "See agent usage and return to sessions that need you.")
                welcomeRow("tray", "A place between apps", "Drop files here, then copy, preview, or AirDrop.")
                welcomeRow("timer", "Focus, notes and more", "Start a timer, keep your Mac awake, or jot something down.")
            }
            Spacer(minLength: 0)
            Text("Clipboard history and calendars are off until you choose to connect them.").font(.caption).foregroundStyle(CrestStyle.secondary)
            HStack { Button("Continue") { model.finishOnboarding() }.buttonStyle(.borderedProminent); Button("Set up connections…") { model.finishOnboarding(); model.openSettings(.connections) }.buttonStyle(.borderless) }
        }.padding(.horizontal, 28).padding(.vertical, 22)
    }
    private func welcomeRow(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 14) { Image(systemName: icon).font(.system(size: 19)).frame(width: 28).foregroundStyle(CrestStyle.blue); VStack(alignment: .leading, spacing: 3) { Text(title).font(.system(size: 12, weight: .semibold)); Text(detail).font(.system(size: 12)).foregroundStyle(CrestStyle.secondary).fixedSize(horizontal: false, vertical: true) } }
    }
}

func rowOpacity(selected: Bool, hovered: Bool) -> Double { selected ? 0.10 : hovered ? 0.07 : 0.04 }

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
    @AppStorage("showFocus") private var showFocus = true
    var body: some View {
        VStack(spacing: 12) {
            if showMedia || showSystem {
                HStack(alignment: .top, spacing: 12) {
                    if showMedia { MediaCard(service: model.media, settings: { model.openSettings(.media) }).frame(maxWidth: .infinity) }
                    if showSystem { SystemCard(model: model).frame(maxWidth: .infinity) }
                }
            }
            if let meeting = model.calendar.meetings.first { MeetingRow(meeting: meeting) }
            ForEach(model.downloads.downloads) { item in DownloadRow(item: item) }
            if showFocus { FocusCard(service: model.focus) }
            if showUsage {
                HStack(alignment: .top, spacing: 12) {
                    QuotaCard(name: "Claude", snapshot: model.agents.claude, connected: model.agents.claude != nil, compact: true, connect: { model.openSettings(.connections) })
                    QuotaCard(name: "Codex", snapshot: model.agents.codex, connected: model.agents.connected, compact: true, connect: { model.openSettings(.connections) })
                }
            }
            if model.energy.enabled { AppEnergyCard(service: model.energy) }
            ForEach(model.bluetooth.devices) { device in Card { Label { VStack(alignment: .leading, spacing: 3) { Text(device.name).font(.system(size: 12, weight: .medium)); Text(device.readings.isEmpty ? "Connected · Battery unavailable" : device.readings.joined(separator: " · ")).font(.caption).foregroundStyle(CrestStyle.secondary) } } icon: { Image(systemName: "airpodspro").font(.title2) } } }
            if !showMedia && !showSystem && !showUsage && !showFocus { EmptyCard(icon: "slider.horizontal.3", title: "Make room for what matters", detail: "Choose the controls you want to see in Settings."); Button("Customize Overview…") { model.openSettings(.general) }.buttonStyle(.bordered) }
        }
    }
}
struct DownloadRow: View {
    var item: DownloadActivity
    var body: some View {
        Card {
            HStack(spacing: 12) {
                ProgressRing(progress: item.fraction, tint: CrestStyle.blue, size: 28, lineWidth: 3) { Image(systemName: "arrow.down").font(.system(size: 11, weight: .bold)) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.path).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    Text("\(ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file)) received · \(ByteCountFormatter.string(fromByteCount: Int64(item.bytesPerSecond), countStyle: .file))/s").font(.caption).foregroundStyle(CrestStyle.secondary)
                }
                Spacer()
                if let fraction = item.fraction { Text(fraction, format: .percent.precision(.fractionLength(0))).font(.system(size: 12, weight: .semibold)).monospacedDigit() }
                else { Image(systemName: "questionmark.circle").foregroundStyle(CrestStyle.tertiary).help("Total size unavailable") }
            }
        }.accessibilityElement(children: .combine)
    }
}
struct SystemCard: View {
    @ObservedObject var model: AppModel
    private var batterySymbol: String {
        if model.power.charging { return "battery.100percent.bolt" }
        guard let percent = model.power.percent else { return "powerplug" }
        return percent > 87 ? "battery.100percent" : percent > 62 ? "battery.75percent" : percent > 37 ? "battery.50percent" : percent > 12 ? "battery.25percent" : "battery.0percent"
    }
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: batterySymbol).foregroundStyle((model.power.percent ?? 100) <= 20 && !model.power.charging ? Color.red : .white)
                    Text(model.power.percent.map { "\($0)%" } ?? "Power").monospacedDigit()
                    Spacer()
                    Text(model.power.charging ? "Connected" : model.power.percent == nil ? "" : "Battery").font(.system(size: 10)).foregroundStyle(CrestStyle.secondary)
                    Button { model.awake.toggle() } label: { Image(systemName: model.awake.active ? "cup.and.saucer.fill" : "cup.and.saucer") }
                        .buttonStyle(RowIconButtonStyle(tint: model.awake.active ? .orange : .white))
                        .help(model.awake.active ? "Stop keeping this Mac awake" : "Keep this Mac awake").accessibilityLabel(model.awake.active ? "Stop keeping awake" : "Keep awake")
                }.font(.system(size: 12, weight: .semibold)).frame(height: 18)
                HStack(spacing: 9) { Button { model.audio.toggleMute() } label: { Image(systemName: model.audio.muted ? "speaker.slash.fill" : "speaker.wave.2.fill").frame(width: 18) }.buttonStyle(.plain).disabled(!model.audio.available).accessibilityLabel("Mute sound"); Slider(value: Binding(get: { Double(model.audio.volume) }, set: { model.audio.set(Float($0)) })).tint(.white).disabled(!model.audio.available).accessibilityLabel("Volume"); Text(model.audio.available ? "\(Int((model.audio.volume * 100).rounded()))" : "—").font(.system(size: 10)).monospacedDigit().frame(width: 22) }
                if model.brightness.available { HStack(spacing: 9) { Image(systemName: "sun.max.fill").frame(width: 18); Slider(value: Binding(get: { Double(model.brightness.value) }, set: { model.brightness.set(Float($0)) })).tint(.white).accessibilityLabel("Brightness"); Text("\(Int((model.brightness.value * 100).rounded()))").font(.system(size: 10)).monospacedDigit().frame(width: 22) } }
                else { Text(model.power.time).font(.system(size: 11)).foregroundStyle(CrestStyle.secondary).lineLimit(2) }
                if model.awake.active, let until = model.awake.until { Text("Awake until \(until.formatted(date: .omitted, time: .shortened))").font(.system(size: 10)).foregroundStyle(.orange.opacity(0.8)) }
            }.frame(height: 116, alignment: .top)
        }
    }
}
struct FocusCard: View {
    @ObservedObject var service: FocusService
    var body: some View {
        Card {
            if service.timer.isActive { TimelineView(.periodic(from: .now, by: 1)) { context in active(at: context.date) } }
            else { idle }
        }
    }
    private var idle: some View {
        HStack(spacing: 10) {
            Image(systemName: "timer").font(.system(size: 15, weight: .medium)).foregroundStyle(.orange).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text("Focus").font(.system(size: 12, weight: .semibold))
                Text("Start a timer").font(.system(size: 10)).foregroundStyle(CrestStyle.secondary)
            }
            Spacer(minLength: 8)
            ForEach(FocusService.presets, id: \.self) { minutes in
                Button("\(minutes)m") { service.start(minutes: minutes) }.buttonStyle(ChipButtonStyle()).help("Start a \(minutes)-minute timer")
            }
        }
    }
    private func active(at date: Date) -> some View {
        let timer = service.timer
        return HStack(spacing: 12) {
            ProgressRing(progress: timer.progress(at: date), tint: .orange, size: 30, lineWidth: 3) {
                Image(systemName: timer.isPaused ? "pause.fill" : "timer").font(.system(size: 11, weight: .semibold))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(TimeFormat.string(timer.remaining(at: date), roundingUp: true)).font(.system(size: 20, weight: .semibold)).monospacedDigit()
                Text(timer.isPaused ? "Paused" : "Ends at \(timer.endsAt?.formatted(date: .omitted, time: .shortened) ?? "—")").font(.system(size: 10)).foregroundStyle(CrestStyle.secondary)
            }
            Spacer()
            Button("+5m") { service.extend(minutes: 5) }.buttonStyle(ChipButtonStyle()).help("Add five minutes")
            Button { if timer.isPaused { service.resume() } else { service.pause() } } label: { Image(systemName: timer.isPaused ? "play.fill" : "pause.fill").frame(width: 14, height: 14) }
                .buttonStyle(QuietButtonStyle()).help(timer.isPaused ? "Resume" : "Pause").accessibilityLabel(timer.isPaused ? "Resume timer" : "Pause timer")
            Button { service.stop() } label: { Image(systemName: "stop.fill").frame(width: 14, height: 14) }
                .buttonStyle(QuietButtonStyle()).help("Stop").accessibilityLabel("Stop timer")
        }
    }
}
struct AppEnergyCard: View {
    @ObservedObject var service: AppEnergyService
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Label("App power", systemImage: "bolt.leaf").font(.system(size: 12, weight: .semibold))
                ForEach(service.readings.prefix(5)) { reading in
                    HStack {
                        Text(reading.name).lineLimit(1)
                        Spacer()
                        if let watts = reading.watts { Text("\(watts, specifier: "%.2f") W").monospacedDigit() }
                        else { Text("\(reading.cpuPercent, specifier: "%.1f")% CPU").monospacedDigit().foregroundStyle(CrestStyle.secondary) }
                    }.font(.system(size: 11)).help("\(reading.processCount) measured processes. Estimate excludes unreported energy.")
                }
                Text(service.status).font(.system(size: 10)).foregroundStyle(CrestStyle.secondary)
            }
        }
    }
}
struct MediaCard: View {
    @ObservedObject var service: MediaService
    var settings: () -> Void
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 10) {
                    Group { if let art = service.artwork { Image(nsImage: art).resizable().scaledToFill() } else { Image(systemName: "music.note").font(.system(size: 20)).foregroundStyle(CrestStyle.secondary) } }
                        .frame(width: 44, height: 44).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10)).clipShape(RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 4) { Text(service.available ? service.title : "Now Playing").font(.system(size: 12, weight: .semibold)).lineLimit(2); Text(service.available ? service.artist : "Music, at your fingertips").font(.system(size: 11)).foregroundStyle(CrestStyle.secondary).lineLimit(1) }
                }
                if service.available {
                    if let position = service.position, position.duration != nil { PlaybackBar(position: position, seek: service.canSeek ? { service.seek(to: $0) } : nil) }
                    HStack(spacing: 25) {
                        Spacer(minLength: 0)
                        Button { service.control("previous") } label: { Image(systemName: "backward.fill") }.accessibilityLabel("Previous track")
                        Button { service.control("toggle") } label: { Image(systemName: service.playing ? "pause.fill" : "play.fill").font(.system(size: 21)).contentTransition(.symbolEffect(.replace)) }.accessibilityLabel(service.playing ? "Pause" : "Play")
                        Button { service.control("next") } label: { Image(systemName: "forward.fill") }.accessibilityLabel("Next track")
                        Spacer(minLength: 0)
                    }.buttonStyle(.plain).frame(height: 28)
                } else {
                    Button("Choose a player…", action: settings).buttonStyle(.bordered).controlSize(.small).padding(.top, 4)
                }
            }.frame(height: 116, alignment: .top)
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
                                if let reset = window.reset {
                                    if compact { Text(reset <= context.date ? "Reset passed" : "Resets in \(TimeFormat.compact(reset.timeIntervalSince(context.date)))").font(.system(size: 9)).foregroundStyle(CrestStyle.tertiary).frame(maxWidth: .infinity, alignment: .leading) }
                                    else { Text(reset <= context.date ? "Reset passed · refresh to update" : "Resets \(reset.formatted(date: .abbreviated, time: .shortened))").font(.system(size: 10)).foregroundStyle(CrestStyle.secondary).frame(maxWidth: .infinity, alignment: .leading) }
                                }
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
            HStack { Text("Sessions").font(.system(size: 12, weight: .semibold)); Spacer(); Text("\(service.sessions.count)").font(.caption).foregroundStyle(CrestStyle.secondary) }
            if service.sessions.isEmpty { EmptyCard(icon: "terminal", title: "No active sessions", detail: "Connect Claude hooks or a shared Codex server to see activity and requests here.") }
            ForEach(service.sessions) { session in sessionRow(session) }
            QuotaCard(name: "Claude", snapshot: service.claude, connected: service.claude != nil, connect: settings)
            QuotaCard(name: "Codex", snapshot: service.codex, connected: service.connected, connect: settings)
            Text(service.status).font(.system(size: 11)).foregroundStyle(CrestStyle.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func sessionRow(_ session: AgentSession) -> some View {
        let waiting = session.state == "Needs you"
        return Button { service.reveal(session) } label: {
            Card {
                HStack(spacing: 10) {
                    Image(systemName: waiting ? "exclamationmark.bubble.fill" : session.state == "Working" ? "ellipsis.circle" : "checkmark.circle")
                        .foregroundStyle(waiting ? Color.pink : session.state == "Working" ? CrestStyle.blue : CrestStyle.secondary)
                        .symbolEffect(.pulse, options: .repeating, isActive: waiting)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(session.project).font(.system(size: 12, weight: .semibold))
                        TimelineView(.periodic(from: .now, by: 30)) { _ in
                            Text("\(session.provider) · \(session.state) · \(session.timestamp.formatted(.relative(presentation: .named)))").font(.system(size: 11)).foregroundStyle(CrestStyle.secondary)
                        }
                    }
                    Spacer(); Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(CrestStyle.secondary)
                }
            }
            .overlay { if waiting { RoundedRectangle(cornerRadius: 16).stroke(Color.pink.opacity(0.5), lineWidth: 1) } }
        }.buttonStyle(.plain).help("Return to this session")
    }
}

struct TrayView: View {
    @ObservedObject var service: TrayService
    @State private var selected = Set<UUID>()
    @State private var search = ""
    @State private var preview: URL?
    @State private var hovered: UUID?
    private var filtered: [TrayItem] { service.items.filter { search.isEmpty || $0.url.lastPathComponent.localizedCaseInsensitiveContains(search) } }
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Label("\(service.items.count) \(service.items.count == 1 ? "item" : "items")", systemImage: "tray").foregroundStyle(CrestStyle.secondary)
                Spacer()
                if service.canUndo { Button("Undo removal") { service.undoRemoval() } }
                if !service.items.isEmpty { Button("Clear") { service.remove(Set(service.items.map(\.id))); selected = [] }.help("Remove every reference; original files are kept") }
                Button { service.choose() } label: { Label("Add", systemImage: "plus") }
            }.font(.caption).controlSize(.small)
            if !service.items.isEmpty { TextField("Search files", text: $search).textFieldStyle(.roundedBorder).accessibilityLabel("Search files") }
            if service.items.isEmpty { EmptyCard(icon: "tray.and.arrow.down", title: "Drop something here", detail: "Keep files within reach as you move between apps. Your originals stay where they are."); Button("Choose files…") { service.choose() }.buttonStyle(.bordered) }
            else if filtered.isEmpty { EmptyCard(icon: "magnifyingglass", title: "No matching files", detail: "Try another name.") }
            ForEach(filtered) { item in row(item) }
            if !service.items.isEmpty {
                HStack { Button(selected.isEmpty ? "Select all" : "Deselect") { selected = selected.isEmpty ? Set(filtered.map(\.id)) : [] }; Spacer(); if !selected.isEmpty { Text("\(selected.count) selected").foregroundStyle(CrestStyle.secondary); Button("Copy") { service.copy(selected) }; Button("AirDrop") { service.share(selected) }; Button("Remove") { service.remove(selected); selected = [] }.help("Remove references; keep original files") } }.font(.caption).controlSize(.small)
            }
            if let feedback = service.feedback { Label(feedback, systemImage: "checkmark.circle").font(.caption).foregroundStyle(CrestStyle.secondary) }
            if let error = service.error { Text(error).font(.caption).foregroundStyle(.orange) }
        }.quickLookPreview($preview)
        .onChange(of: search) { _, _ in selected = [] }
        .onChange(of: preview) { _, value in service.onInteraction?(value != nil) }
        .onDisappear { service.onInteraction?(false) }
        .onChange(of: service.items.map(\.id)) { _, ids in selected.formIntersection(ids) }
    }
    private func row(_ item: TrayItem) -> some View {
        let url = item.url, exists = item.exists, isSelected = selected.contains(item.id), isHovered = hovered == item.id
        return HStack(spacing: 10) {
            Toggle("Select \(url.lastPathComponent)", isOn: selection(item.id)).toggleStyle(.checkbox).labelsHidden()
            FileThumbnail(url: url, size: 34).opacity(exists ? 1 : 0.4)
            VStack(alignment: .leading, spacing: 3) {
                Text(url.lastPathComponent).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                Text(exists ? item.detail : "File unavailable").font(.system(size: 10)).foregroundStyle(exists ? CrestStyle.secondary : .orange).lineLimit(1)
            }
            Spacer(minLength: 0)
            HStack(spacing: 2) {
                Button { preview = url } label: { Image(systemName: "eye") }.help("Quick Look").accessibilityLabel("Preview \(url.lastPathComponent)")
                Button { NSWorkspace.shared.open(url) } label: { Image(systemName: "arrow.up.forward.app") }.help("Open").accessibilityLabel("Open \(url.lastPathComponent)")
                Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: { Image(systemName: "folder") }.help("Reveal in Finder").accessibilityLabel("Reveal \(url.lastPathComponent) in Finder")
            }.buttonStyle(RowIconButtonStyle()).disabled(!exists).opacity(isHovered || isSelected ? 1 : 0.5)
        }
        .padding(10)
        .background(.white.opacity(rowOpacity(selected: isSelected, hovered: isHovered)), in: RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onHover { inside in hovered = inside ? item.id : (hovered == item.id ? nil : hovered) }
        .onTapGesture(count: 2) { if exists { NSWorkspace.shared.open(url) } }
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .help(exists ? "Double-click to open · drag into another app" : "The original was moved or deleted")
    }
    private func selection(_ id: UUID) -> Binding<Bool> { Binding(get: { selected.contains(id) }, set: { if $0 { selected.insert(id) } else { selected.remove(id) } }) }
}

enum ClipFilter: String, CaseIterable, Identifiable {
    case all = "All", pinned = "Pinned", links = "Links", images = "Images"
    var id: String { rawValue }
    func matches(_ item: ClipItem) -> Bool {
        switch self {
        case .all: return true
        case .pinned: return item.pinned
        case .links: return item.kind == .link
        case .images: return item.kind == .image
        }
    }
}
struct ClipboardView: View {
    @ObservedObject var service: ClipboardService
    var settings: () -> Void
    @State private var selected = Set<UUID>()
    @State private var search = ""
    @State private var filter = ClipFilter.all
    @State private var hovered: UUID?
    @State private var copied: UUID?
    private var filtered: [ClipItem] { service.items.filter { filter.matches($0) && (search.isEmpty || ($0.text ?? "Image").localizedCaseInsensitiveContains(search)) }.sorted { $0.pinned != $1.pinned ? $0.pinned : $0.created > $1.created } }
    var body: some View {
        VStack(spacing: 10) {
            if !service.enabled { EmptyCard(icon: "lock.shield", title: "Your clipboard. Your choice.", detail: service.error ?? "Keep an encrypted history of text and images on this Mac. Password managers and concealed items are excluded."); Button("Set up clipboard history…", action: settings).buttonStyle(.bordered) }
            else {
                TextField("Search clipboard", text: $search).textFieldStyle(.roundedBorder)
                HStack(spacing: 4) {
                    ForEach(ClipFilter.allCases) { option in Button(option.rawValue) { filter = option }.buttonStyle(ChipButtonStyle(selected: filter == option)) }
                    Spacer()
                    Label("\(service.items.count)", systemImage: "lock").foregroundStyle(CrestStyle.secondary).help("\(service.items.count) items, encrypted on this Mac")
                    Button(selected.isEmpty ? "Select all" : "Deselect") { selected = selected.isEmpty ? Set(filtered.map(\.id)) : [] }
                }.font(.caption)
                ForEach(filtered) { item in row(item) }
                if filtered.isEmpty { EmptyCard(icon: search.isEmpty && filter == .all ? "doc.on.clipboard" : "magnifyingglass", title: search.isEmpty && filter == .all ? "Nothing saved yet" : "No matches", detail: search.isEmpty && filter == .all ? "Copy something in another app to start your history." : "Try another search or filter.") }
                if !selected.isEmpty { HStack { Text("\(selected.count) selected").foregroundStyle(CrestStyle.secondary); Button("Copy") { service.copy(selected) }; Button("AirDrop") { service.share(selected) }; Spacer(); Button("Delete saved items") { service.delete(selected); selected = [] } }.font(.caption).controlSize(.small) }
                if let feedback = service.feedback { Text(feedback).font(.caption).foregroundStyle(CrestStyle.secondary) }
                if let error = service.error { Text(error).font(.caption).foregroundStyle(.orange) }
            }
        }
        .onChange(of: search) { _, _ in selected = [] }
        .onChange(of: filter) { _, _ in selected = [] }
        .onChange(of: service.items.map(\.id)) { _, ids in selected.formIntersection(ids) }
    }
    private func row(_ item: ClipItem) -> some View {
        let isSelected = selected.contains(item.id), isHovered = hovered == item.id, kind = item.kind
        return HStack(spacing: 10) {
            Toggle("Select clipboard item", isOn: Binding(get: { selected.contains(item.id) }, set: { if $0 { selected.insert(item.id) } else { selected.remove(item.id) } })).toggleStyle(.checkbox).labelsHidden()
            Button { copy(item) } label: {
                HStack(spacing: 10) {
                    thumbnail(item, kind: kind)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.text ?? "Image").font(.system(size: 12)).lineLimit(3).foregroundStyle(kind == .link ? CrestStyle.blue : .white)
                        HStack(spacing: 4) {
                            TimelineView(.periodic(from: .now, by: 30)) { _ in Text(item.created.formatted(.relative(presentation: .named))) }
                            if copied == item.id { Label("Copied", systemImage: "checkmark").foregroundStyle(.green) }
                        }.font(.system(size: 10)).foregroundStyle(CrestStyle.secondary)
                    }
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).help("Click to copy")
            HStack(spacing: 2) {
                if isHovered, let link = item.link { Button { NSWorkspace.shared.open(link) } label: { Image(systemName: "arrow.up.right.square") }.help("Open link").accessibilityLabel("Open link") }
                if isHovered || item.pinned {
                    Button { service.pin(item.id) } label: { Image(systemName: item.pinned ? "pin.fill" : "pin") }
                        .buttonStyle(RowIconButtonStyle(tint: item.pinned ? CrestStyle.blue : .white)).help(item.pinned ? "Unpin" : "Pin").accessibilityLabel(item.pinned ? "Unpin item" : "Pin item")
                }
                if isHovered { Button { service.delete([item.id]) } label: { Image(systemName: "trash") }.help("Delete").accessibilityLabel("Delete item") }
            }.buttonStyle(RowIconButtonStyle())
        }
        .padding(10)
        .background(.white.opacity(rowOpacity(selected: isSelected, hovered: isHovered)), in: RoundedRectangle(cornerRadius: 12))
        .onHover { inside in hovered = inside ? item.id : (hovered == item.id ? nil : hovered) }
        .onDrag { if let data = item.image, let image = NSImage(data: data) { return NSItemProvider(object: image) }; return NSItemProvider(object: (item.text ?? "") as NSString) }
    }
    @ViewBuilder private func thumbnail(_ item: ClipItem, kind: ClipKind) -> some View {
        if let data = item.image, let image = NSImage(data: data) {
            Image(nsImage: image).resizable().scaledToFill().frame(width: 36, height: 36).clipShape(RoundedRectangle(cornerRadius: 7))
        } else if let color = item.color {
            RoundedRectangle(cornerRadius: 7).fill(Color(red: color.red, green: color.green, blue: color.blue)).frame(width: 36, height: 36)
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(.white.opacity(0.2), lineWidth: 0.5))
        } else {
            Image(systemName: kind == .link ? "link" : "text.alignleft").font(.system(size: 13)).foregroundStyle(kind == .link ? CrestStyle.blue : CrestStyle.secondary)
                .frame(width: 36, height: 36).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
        }
    }
    private func copy(_ item: ClipItem) {
        service.copy([item.id]); copied = item.id
        Task { try? await Task.sleep(for: .seconds(1.5)); if copied == item.id { copied = nil } }
    }
}

struct NotesView: View {
    @ObservedObject var service: NotesService
    @Binding var editing: Bool
    @FocusState private var focused: Bool
    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $service.text)
                    .font(.system(size: 13)).scrollContentBackground(.hidden)
                    .focused($focused).padding(.horizontal, 6).padding(.vertical, 8)
                    .accessibilityLabel("Notes")
                if service.text.isEmpty {
                    Text("Jot something down…").font(.system(size: 13)).foregroundStyle(CrestStyle.tertiary)
                        .padding(.horizontal, 11).padding(.vertical, 8).allowsHitTesting(false)
                }
            }
            .frame(height: 318)
            .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(focused ? 0.2 : 0.07), lineWidth: 0.5))
            HStack(spacing: 8) {
                Label("Saved on this Mac", systemImage: "internaldrive").foregroundStyle(CrestStyle.tertiary)
                Text("\(service.words) \(service.words == 1 ? "word" : "words")").monospacedDigit().foregroundStyle(CrestStyle.tertiary)
                Spacer()
                if service.canUndoClear { Button("Undo clear") { service.undoClear() } }
                Button("Copy") { service.copy() }.disabled(service.text.isEmpty)
                Button("Clear") { service.clear() }.disabled(service.text.isEmpty)
            }.font(.caption).controlSize(.small)
            if let error = service.error { Text(error).font(.caption).foregroundStyle(.orange) }
        }
        .onChange(of: focused) { _, value in editing = value }
        .onDisappear { editing = false }
    }
}

struct MeetingRow: View {
    var meeting: Meeting
    var body: some View {
        Card {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 2).fill(Color.red.opacity(0.85)).frame(width: 4, height: 34)
                VStack(alignment: .leading, spacing: 4) {
                    Text(meeting.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(meeting.start > context.date ? "In \(TimeFormat.compact(meeting.start.timeIntervalSince(context.date))) · \(meeting.start.formatted(date: .omitted, time: .shortened))" : "In progress · ends \(meeting.end.formatted(date: .omitted, time: .shortened))")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let url = meeting.link { Link(destination: url) { Label("Join", systemImage: "video.fill") }.buttonStyle(.borderedProminent).tint(.green).controlSize(.small) }
            }
        }
    }
}
