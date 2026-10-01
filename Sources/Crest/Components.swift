import SwiftUI
import AppKit
import QuickLookThumbnailing
import CrestCore

enum HoverOpen: String, CaseIterable, Identifiable {
    case instant, short, relaxed, click
    var id: String { rawValue }
    var title: String {
        switch self {
        case .instant: return "Instantly"
        case .short: return "After a short pause"
        case .relaxed: return "After a longer pause"
        case .click: return "Only when clicked"
        }
    }
    /// A short pause avoids opening when the pointer passes on its way to the menu bar.
    var delay: Double? {
        switch self {
        case .instant: return 0
        case .short: return 0.12
        case .relaxed: return 0.35
        case .click: return nil
        }
    }
}

struct ChipButtonStyle: ButtonStyle {
    var selected = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold)).monospacedDigit()
            .padding(.horizontal, 9).padding(.vertical, 5)
            .foregroundStyle(selected ? .black : .white.opacity(enabled ? 0.92 : 0.4))
            .background(selected ? Color.white.opacity(0.9) : Color.white.opacity(configuration.isPressed ? 0.2 : 0.08), in: Capsule())
            .contentShape(Capsule())
    }
}

/// Small icon buttons inside rows: a fixed hit area with a hover highlight.
struct RowIconButtonStyle: ButtonStyle {
    var tint: Color = .white
    func makeBody(configuration: Configuration) -> some View { RowIcon(configuration: configuration, tint: tint) }
    private struct RowIcon: View {
        let configuration: ButtonStyleConfiguration
        let tint: Color
        @State private var hovering = false
        var body: some View {
            configuration.label.font(.system(size: 11, weight: .medium))
                .foregroundStyle(tint.opacity(hovering ? 1 : 0.72))
                .frame(width: 24, height: 24)
                .background(.white.opacity(configuration.isPressed ? 0.18 : hovering ? 0.1 : 0), in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}

struct ProgressRing<Content: View>: View {
    var progress: Double?
    var tint: Color
    var size: CGFloat = 18
    var lineWidth: CGFloat = 2
    @ViewBuilder var label: Content
    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.25), lineWidth: lineWidth)
            if let progress {
                Circle().trim(from: 0, to: max(0.002, min(1, progress)))
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            label.foregroundStyle(tint)
        }.frame(width: size, height: size)
    }
}

struct LevelBar: View {
    var value: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        GeometryReader { proxy in
            Capsule().fill(.white.opacity(0.16)).overlay(alignment: .leading) {
                Capsule().fill(.white).frame(width: value > 0 ? max(5, proxy.size.width * min(1, value)) : 0)
            }
        }
        .frame(height: 5)
        .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: value)
    }
}

/// The collapsed-notch message line. Volume and brightness render as a HUD bar.
struct NoticeView: View {
    var notice: Notice
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: notice.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(notice.urgent ? Color.pink : .white)
                .frame(width: 20)
                .contentTransition(.symbolEffect(.replace))
            if let level = notice.level {
                LevelBar(value: level)
                Text("\(Int((level * 100).rounded()))")
                    .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                    .frame(width: 26, alignment: .trailing)
                    .contentTransition(.numericText(value: level))
            } else {
                Text(notice.text)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(notice.urgent ? Color.pink : .white)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(notice.text)
    }
}

/// Elapsed/remaining time with an optional drag-to-seek track.
struct PlaybackBar: View {
    var position: PlaybackPosition
    var seek: ((Double) -> Void)?
    @State private var scrub: Double?
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let duration = position.duration ?? 0
            let elapsed = scrub ?? position.elapsed(at: context.date)
            VStack(spacing: 2) {
                GeometryReader { proxy in
                    let fraction = duration > 0 ? min(1, max(0, elapsed / duration)) : 0
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.14))
                        Capsule().fill(.white.opacity(scrub == nil ? 0.75 : 1)).frame(width: max(3, proxy.size.width * fraction))
                    }
                    .frame(height: scrub == nil ? 3 : 5)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard seek != nil, duration > 0 else { return }
                            scrub = min(1, max(0, value.location.x / max(1, proxy.size.width))) * duration
                        }
                        .onEnded { _ in
                            if let target = scrub { seek?(target) }
                            scrub = nil
                        })
                }
                .frame(height: 10)
                HStack {
                    Text(TimeFormat.string(elapsed))
                    Spacer()
                    Text("-" + TimeFormat.string(max(0, duration - elapsed)))
                }
                .font(.system(size: 9, weight: .medium)).monospacedDigit()
                .foregroundStyle(CrestStyle.tertiary)
            }
        }
        .help(seek == nil ? "" : "Drag to seek")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(TimeFormat.string(position.elapsed(at: Date()))) of \(TimeFormat.string(position.duration ?? 0))")
    }
}

/// Quick Look thumbnail with the Finder icon as a fallback.
struct FileThumbnail: View {
    let url: URL
    var size: CGFloat = 32
    @State private var image: NSImage?
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 5)) }
            else { Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable() }
        }
        .frame(width: size, height: size)
        .task(id: url) { image = await ThumbnailCache.shared.image(for: url, size: size) }
    }
}

@MainActor final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()
    init() { cache.countLimit = 200 }
    func image(for url: URL, size: CGFloat) async -> NSImage? {
        let key = "\(url.path)#\(Int(size))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: size, height: size), scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
        guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else { return nil }
        let image = representation.nsImage
        cache.setObject(image, forKey: key)
        return image
    }
}
