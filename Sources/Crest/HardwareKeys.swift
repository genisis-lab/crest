import AppKit
import ApplicationServices
import CrestCore

/// Optional event tap only for macOS system-defined media-key events.
/// Ordinary keyboard events are neither requested nor recorded.
@MainActor final class HardwareKeyService: ObservableObject {
    @Published var enabled = false
    @Published var status = "System overlays remain enabled."
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var consumed = Set<Int>()
    private weak var audio: AudioService?
    private weak var brightness: BrightnessService?
    var onChange: ((String) -> Void)?
    func enable(_ value: Bool, audio: AudioService, brightness: BrightnessService) {
        stop(); self.audio = audio; self.brightness = brightness
        guard value else { return }
        guard AXIsProcessTrusted() else { status = "Allow Crest in System Settings → Privacy & Security → Accessibility, then enable this option again."; return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let created = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: CGEventMask(1 << 14), callback: { _, type, event, pointer in
            guard let pointer else { return Unmanaged.passUnretained(event) }
            return MainActor.assumeIsolated {
                let service = Unmanaged<HardwareKeyService>.fromOpaque(pointer).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = service.tap, service.enabled { CGEvent.tapEnable(tap: tap, enable: true) }
                    return Unmanaged.passUnretained(event)
                }
                guard type.rawValue == 14, let nsEvent = NSEvent(cgEvent: event), nsEvent.subtype.rawValue == 8,
                      let key = HardwareKey(data1: nsEvent.data1), service.handle(key, fine: nsEvent.modifierFlags.contains([.shift, .option])) else { return Unmanaged.passUnretained(event) }
                return nil
            }
        }, userInfo: context) else { status = "macOS did not allow the media-key tap. System keys continue to work normally."; return }
        tap = created; source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
        enabled = true; CGEvent.tapEnable(tap: created, enable: true)
        status = "Supported hardware keys use Crest's overlay. Unsupported devices and software controls retain the system overlay."
    }
    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil; tap = nil; consumed = []; enabled = false; status = "System overlays remain enabled."
    }
    private func handle(_ key: HardwareKey, fine: Bool) -> Bool {
        guard enabled else { return false }
        if !key.down { return consumed.remove(key.code) != nil }
        let step: Float = fine ? 1 / 64 : 1 / 16
        var success = false
        switch key.code {
        case 0, 1:
            if let audio, audio.available { success = audio.set(audio.volume + (key.code == 0 ? step : -step)); if success { onChange?("Volume · \(Int((audio.volume * 100).rounded()))%") } }
        case 7:
            if key.repeated { return consumed.contains(key.code) }
            if let audio { success = audio.toggleMute(); if success { onChange?(audio.muted ? "Muted" : "Sound on") } }
        case 2, 3:
            if let brightness, brightness.available { success = brightness.set(brightness.value + (key.code == 2 ? step : -step)); if success { onChange?("Brightness · \(Int((brightness.value * 100).rounded()))%") } }
        default: break
        }
        if success { consumed.insert(key.code) }
        return success
    }
}
