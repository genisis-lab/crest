import AppKit
import IOKit.pwr_mgt
import CrestCore

/// Focus countdown. The end date is persisted so a running timer survives relaunch.
@MainActor final class FocusService: ObservableObject {
    static let presets = [5, 15, 25, 45]
    @Published private(set) var timer: FocusTimer
    var onFinish: (() -> Void)?
    private var ticker: Timer?
    init() {
        var saved = UserDefaults.standard.data(forKey: "focusTimer").flatMap { try? JSONDecoder().decode(FocusTimer.self, from: $0) } ?? FocusTimer()
        // A session that ended while Crest was closed is cleared quietly.
        if saved.isFinished(at: Date()) { saved.reset() }
        timer = saved
        schedule()
    }
    func start(minutes: Int) { timer.start(TimeInterval(minutes) * 60, at: Date()); changed() }
    func pause() { timer.pause(at: Date()); changed() }
    func resume() { timer.resume(at: Date()); changed() }
    func extend(minutes: Int) { timer.extend(by: TimeInterval(minutes) * 60, at: Date()); changed() }
    func stop() { timer.reset(); changed() }
    /// Wall-clock timers do not fire during sleep; wake re-checks the deadline.
    func refresh() { if timer.isFinished(at: Date()) { complete() } else { schedule() } }
    private func changed() {
        UserDefaults.standard.set(try? JSONEncoder().encode(timer), forKey: "focusTimer")
        schedule()
    }
    private func schedule() {
        ticker?.invalidate(); ticker = nil
        guard let end = timer.endsAt else { return }
        let next = Timer(fire: max(end, Date()), interval: 0, repeats: false) { [weak self] _ in Task { @MainActor in self?.refresh() } }
        RunLoop.main.add(next, forMode: .common); ticker = next
    }
    private func complete() {
        guard timer.isRunning else { return }
        timer.reset(); changed(); onFinish?()
    }
}

/// Prevents idle display sleep through a named power assertion. Never persisted across launches.
@MainActor final class AwakeService: ObservableObject {
    static let durations: [(String, TimeInterval?)] = [("For 30 minutes", 1800), ("For 1 hour", 3600), ("For 2 hours", 7200), ("Until turned off", nil)]
    @Published private(set) var active = false
    @Published private(set) var until: Date?
    private var assertion: IOPMAssertionID = 0
    private var expiry: Timer?
    func enable(for duration: TimeInterval?) {
        disable()
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "Crest is keeping this Mac awake" as CFString, &id)
        guard result == kIOReturnSuccess else { return }
        assertion = id; active = true
        if let duration {
            until = Date().addingTimeInterval(duration)
            let timer = Timer(timeInterval: duration, repeats: false) { [weak self] _ in Task { @MainActor in self?.disable() } }
            RunLoop.main.add(timer, forMode: .common); expiry = timer
        }
    }
    func disable() {
        expiry?.invalidate(); expiry = nil
        if active { IOPMAssertionRelease(assertion) }
        assertion = 0; active = false; until = nil
    }
    func toggle() { if active { disable() } else { enable(for: nil) } }
}

/// A single scratchpad saved with owner-only permissions in Application Support.
@MainActor final class NotesService: ObservableObject {
    @Published var text = "" { didSet { textChanged() } }
    @Published private(set) var error: String?
    @Published private(set) var canUndoClear = false
    private var cleared: String?
    private var saveTask: Task<Void, Never>?
    private var readOnly = false
    private let file = CrestPaths.root.appendingPathComponent("notes.txt")
    init() {
        do { text = try String(contentsOf: file, encoding: .utf8) }
        catch let failure as CocoaError where failure.code == .fileReadNoSuchFile || failure.code == .fileNoSuchFile {}
        catch { readOnly = true; self.error = "Saved notes could not be read. Changes will not be saved until Crest can read them again." }
    }
    var words: Int { text.split { $0.isWhitespace || $0.isNewline }.count }
    func clear() { guard !text.isEmpty else { return }; let previous = text; text = ""; cleared = previous; canUndoClear = true }
    func undoClear() { guard let cleared else { return }; text = cleared }
    func copy() { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
    private func textChanged() {
        if !text.isEmpty { cleared = nil; canUndoClear = false }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }
    func save() {
        saveTask?.cancel(); saveTask = nil
        guard !readOnly else { return }
        do { try CrestPaths.save(Data(text.utf8), to: file); error = nil }
        catch { self.error = "Notes could not be saved: \(error.localizedDescription)" }
    }
}
