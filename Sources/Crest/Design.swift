import AppKit
import SwiftUI

/// One glass surface for the floating shell, solid data surfaces inside it.
struct NotchMaterial: ViewModifier {
    var enabled: Bool
    var expanded: Bool
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency
    @Environment(\.colorSchemeContrast) var contrast
    private var shape: UnevenRoundedRectangle { .init(bottomLeadingRadius: expanded ? 25 : 14, bottomTrailingRadius: expanded ? 25 : 14) }
    @ViewBuilder func body(content: Content) -> some View {
        if enabled && !reduceTransparency && contrast != .increased {
            if #available(macOS 26, *) {
                GlassEffectContainer { content.background(.black.opacity(0.22), in: shape).glassEffect(.regular.tint(.black.opacity(0.4)), in: shape) }
            } else { content.background(.regularMaterial, in: shape).overlay(shape.stroke(.white.opacity(0.12), lineWidth: 0.5)) }
        } else {
            content.background(Color(red: 0.035, green: 0.038, blue: 0.045), in: shape)
                .overlay(shape.stroke(.white.opacity(contrast == .increased ? 0.7 : 0.08), lineWidth: contrast == .increased ? 1.5 : 0.5))
        }
    }
}

/// Interruptible, critically damped window motion. A new target keeps its velocity.
@MainActor final class PanelSpring {
    private var timer: Timer?
    private weak var panel: NSPanel?
    private var current = [CGFloat](repeating: 0, count: 4)
    private var velocity = [CGFloat](repeating: 0, count: 4)
    private var target = [CGFloat](repeating: 0, count: 4)
    private var last = Date()
    func move(_ panel: NSPanel, to rect: NSRect, immediately: Bool) {
        self.panel = panel
        let next = [rect.midX, rect.maxY, rect.width, rect.height]
        if immediately {
            timer?.invalidate(); timer = nil; target = next; current = next; velocity = .init(repeating: 0, count: 4); panel.setFrame(rect, display: true); return
        }
        if target == next { return }
        target = next
        if timer == nil {
            let frame = panel.frame; current = [frame.midX, frame.maxY, frame.width, frame.height]; last = Date()
            timer = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] _ in Task { @MainActor in self?.step() } }
        }
    }
    private func step() {
        let now = Date(); let dt = min(0.032, now.timeIntervalSince(last)); last = now
        var settled = true
        for i in 0..<4 {
            let acceleration = 400 * (target[i] - current[i]) - 40 * velocity[i]
            velocity[i] += acceleration * dt; current[i] += velocity[i] * dt
            if abs(current[i] - target[i]) > 0.2 || abs(velocity[i]) > 0.2 { settled = false }
        }
        if settled { current = target; velocity = .init(repeating: 0, count: 4); timer?.invalidate(); timer = nil }
        panel?.setFrame(NSRect(x: current[0] - current[2] / 2, y: current[1] - current[3], width: current[2], height: current[3]), display: true)
    }
}
