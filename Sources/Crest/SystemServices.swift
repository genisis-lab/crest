import AppKit
import CoreAudio
import AudioToolbox
import IOKit.ps
import EventKit
import Darwin

@MainActor final class PowerService: ObservableObject {
    @Published var percent: Int?
    @Published var charging = false
    @Published var time: String = ""
    var onCharge: ((String) -> Void)?
    private var source: CFRunLoopSource?
    init() {
        refresh()
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let created = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let service = Unmanaged<PowerService>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in service.refresh() }
        }, context)?.takeRetainedValue() { source = created; CFRunLoopAddSource(CFRunLoopGetMain(), created, .defaultMode) }
    }
    func refresh() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(), let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for power in list {
            guard let d = IOPSGetPowerSourceDescription(info, power)?.takeUnretainedValue() as? [String: Any], d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let current = d[kIOPSCurrentCapacityKey] as? Int ?? 0, maxValue = d[kIOPSMaxCapacityKey] as? Int ?? 100
            percent = maxValue > 0 ? min(100, max(0, current * 100 / maxValue)) : nil
            let next = d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            if next && !charging { onCharge?("Power connected · \(percent ?? 0)%") }; charging = next
            let minutes = d[next ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey] as? Int ?? -1
            time = minutes > 0 ? "\(minutes / 60)h \(minutes % 60)m \(next ? "to full" : "remaining")" : next ? "Connected to power" : "Time estimate unavailable"
        }
    }
}

@MainActor final class AudioService: ObservableObject {
    @Published var volume: Float = 0
    @Published var available = false
    @Published var muted = false
    var onChange: ((String) -> Void)?
    private var timer: Timer?
    private var initialized = false
    init() { refresh(); timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } } }
    private func device() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var id: AudioObjectID = 0; var size = UInt32(MemoryLayout.size(ofValue: id))
        return AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr && id != 0 ? id : nil
    }
    func refresh() {
        guard let id = device() else { available = false; return }
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var value: Float32 = 0; var size = UInt32(MemoryLayout.size(ofValue: value))
        let success = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr
        available = success
        if success {
            if initialized && abs(value - volume) > 0.015 { onChange?("Volume · \(Int(value * 100))%") }
            volume = value; initialized = true
        }
        address.mSelector = kAudioDevicePropertyMute; var mute: UInt32 = 0; size = 4
        if AudioObjectGetPropertyData(id, &address, 0, nil, &size, &mute) == noErr { muted = mute != 0 }
    }
    func set(_ value: Float) {
        guard let id = device() else { return }
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var volume = min(1, max(0, value)); AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout.size(ofValue: volume)), &volume); refresh()
    }
    func toggleMute() {
        guard let id = device() else { return }
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = muted ? 0 : 1; AudioObjectSetPropertyData(id, &address, 0, nil, 4, &value); refresh()
    }
}

// Compatibility adapter: private DisplayServices is isolated and dynamically resolved.
@MainActor final class BrightnessService: ObservableObject {
    typealias Get = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    typealias Set = @convention(c) (UInt32, Float) -> Int32
    @Published var available = false
    @Published var value: Float = 0
    var onChange: ((String) -> Void)?
    private var getValue: Get?
    private var setValue: Set?
    private var timer: Timer?
    private var initialized = false
    func enable(_ enabled: Bool) {
        timer?.invalidate(); timer = nil; available = false
        guard enabled else { return }
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY), let get = dlsym(handle, "DisplayServicesGetBrightness"), let set = dlsym(handle, "DisplayServicesSetBrightness") else { return }
        getValue = unsafeBitCast(get, to: Get.self); setValue = unsafeBitCast(set, to: Set.self)
        refresh(); timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } }
    }
    private var display: UInt32 { NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 ?? CGMainDisplayID() }
    func refresh() {
        var next: Float = 0; available = getValue?(display, &next) == 0
        if available { if initialized && abs(next - value) > 0.015 { onChange?("Brightness · \(Int(next * 100))%") }; value = next; initialized = true }
    }
    func set(_ value: Float) { if setValue?(display, min(1, max(0, value))) == 0 { refresh() } }
}

struct Meeting: Identifiable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var link: URL?
}
@MainActor final class CalendarService: ObservableObject {
    @Published var meetings: [Meeting] = []
    @Published var status = "Connect your calendars to see upcoming meetings."
    @Published var enabled = false
    private let store = EKEventStore()
    private var timer: Timer?
    func connect() async {
        do {
            guard try await store.requestFullAccessToEvents() else { status = "Calendar access is off. Enable it in System Settings to connect."; return }
            enabled = true; refresh(); timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } }
        } catch { status = error.localizedDescription }
    }
    func disconnect() { enabled = false; timer?.invalidate(); timer = nil; meetings = []; status = "Calendar disconnected." }
    func refresh() {
        guard enabled else { return }
        let now = Date(); let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-3600), end: now.addingTimeInterval(86400), calendars: nil)
        meetings = store.events(matching: predicate).filter { event in
            !event.isAllDay && event.endDate > now && event.status != .canceled && !(event.attendees ?? []).contains { $0.isCurrentUser && $0.participantStatus == .declined }
        }.sorted { $0.startDate < $1.startDate }.prefix(8).map { event in
            Meeting(id: (event.eventIdentifier ?? UUID().uuidString) + String(event.startDate.timeIntervalSince1970), title: event.title ?? "Meeting", start: event.startDate, end: event.endDate, link: Self.joinLink(event))
        }
        status = meetings.isEmpty ? "No meetings in the next 24 hours." : "\(meetings.count) upcoming"
    }
    private static func joinLink(_ event: EKEvent) -> URL? {
        let text = [event.url?.absoluteString, event.location, event.notes].compactMap { $0 }.joined(separator: " ")
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let links = detector?.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap(\.url) ?? []
        let domains = ["zoom.us", "zoom.com", "meet.google.com", "teams.microsoft.com", "teams.live.com", "webex.com"]
        return links.first { url in guard url.scheme == "https", let host = url.host?.lowercased() else { return false }; return domains.contains { host == $0 || host.hasSuffix("." + $0) } }
    }
}

struct Earbud: Identifiable { var id: String { name }; var name: String; var readings: [String]; var connected: Bool }
@MainActor final class BluetoothService: ObservableObject {
    @Published var devices: [Earbud] = []
    @Published var status = "Enable Bluetooth monitoring in Settings."
    var onConnect: ((String) -> Void)?
    private var timer: Timer?
    private var busy = false
    private var enabled = false
    func enable(_ value: Bool) {
        timer?.invalidate(); timer = nil; enabled = value
        guard value else { devices = []; status = "Bluetooth monitoring off"; return }
        refresh(); timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } }
    }
    func refresh() {
        guard !busy, enabled else { return }; busy = true
        Task.detached { [weak self] in
            let p = Process(); let pipe = Pipe(); p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler"); p.arguments = ["SPBluetoothDataType", "-json"]; p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
            var result: [Earbud] = []
            if (try? p.run()) != nil {
                DispatchQueue.global().asyncAfter(deadline: .now() + 20) { if p.isRunning { p.terminate() } }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let json = try? JSONSerialization.jsonObject(with: data) { result = Self.parse(json) }
            }
            let captured = result
            await MainActor.run {
                guard let self else { return }; self.busy = false; guard self.enabled else { return }
                for d in captured where d.connected && !self.devices.contains(where: { $0.name == d.name && $0.connected }) { self.onConnect?(d.name + " connected") }
                self.devices = captured; self.status = captured.isEmpty ? "No connected battery-reporting devices. Some AirPods readings are unavailable on this macOS version." : "OS-reported readings · refreshed every minute"
            }
        }
    }
    nonisolated private static func parse(_ object: Any, connected: Bool = false) -> [Earbud] {
        var result: [Earbud] = []
        if let array = object as? [Any] { return array.flatMap { parse($0, connected: connected) } }
        guard let dict = object as? [String: Any] else { return [] }
        for (key, value) in dict {
            if let entry = value as? [String: Any] {
                let readings = entry.keys.sorted().filter { $0.lowercased().contains("battery") }.compactMap { field -> String? in
                    guard let raw = entry[field] as? String else { return nil }
                    let label = field.contains("left") ? "Left" : field.contains("right") ? "Right" : field.contains("case") ? "Case" : "Battery"
                    return "\(label) \(raw)"
                }
                if connected && (!readings.isEmpty || key.lowercased().contains("airpods")) { result.append(Earbud(name: key, readings: readings, connected: true)) }
                else { result += parse(entry, connected: connected || key == "device_connected") }
            } else if value is [Any] { result += parse(value, connected: connected || key == "device_connected") }
        }
        return result
    }
}
