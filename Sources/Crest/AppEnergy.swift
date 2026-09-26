import AppKit
import Darwin
import CrestCore

struct AppEnergyReading: Identifiable {
    var id: String
    var name: String
    var watts: Double?
    var cpuPercent: Double
    var processCount: Int
}

@MainActor final class AppEnergyService: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var readings: [AppEnergyReading] = []
    @Published private(set) var status = "App power monitoring is off."
    private var previous: [Int32: EnergyProcess] = [:]
    private var lastSample: TimeInterval?
    private var timer: Timer?
    private var generation = 0
    private var busy = false
    func configure(_ value: Bool) {
        generation += 1; timer?.invalidate(); timer = nil
        enabled = value; readings = []; previous = [:]; lastSample = nil
        status = value ? "Measuring app activity…" : "App power monitoring is off."
        guard value else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } }
        timer?.tolerance = 1
    }
    private func refresh() {
        guard enabled, !busy else { return }; busy = true
        let requestedGeneration = generation
        let apps = NSWorkspace.shared.runningApplications.compactMap { app -> EnergyApplication? in
            guard let url = app.bundleURL, app.activationPolicy != .prohibited else { return nil }
            return EnergyApplication(path: url.path, name: app.localizedName ?? url.deletingPathExtension().lastPathComponent)
        }.sorted { $0.path.count > $1.path.count }
        Task { [weak self] in
            let snapshot = await Task.detached { EnergyProcess.capture(apps) }.value
            guard let self else { return }; busy = false
            guard enabled && requestedGeneration == generation else { return }
            let now = ProcessInfo.processInfo.systemUptime
            defer { previous = snapshot; lastSample = now }
            guard let lastSample else { return }
            var grouped: [String: AppEnergyReading] = [:]
            for (pid, current) in snapshot {
                guard let old = previous[pid], old.app.path == current.app.path,
                      let activity = ProcessActivity(previous: old.counters, current: current.counters, elapsed: now - lastSample) else { continue }
                var row = grouped[current.app.path] ?? AppEnergyReading(id: current.app.path, name: current.app.name, watts: nil, cpuPercent: 0, processCount: 0)
                row.cpuPercent += activity.cpuPercent; row.processCount += 1
                if let watts = activity.watts { row.watts = (row.watts ?? 0) + watts }
                grouped[row.id] = row
            }
            readings = grouped.values.sorted { ($0.watts ?? -1, $0.cpuPercent) > ($1.watts ?? -1, $1.cpuPercent) }
            status = readings.isEmpty ? "Waiting for comparable process samples…" : readings.contains { $0.watts != nil } ? "OS-estimated process power · 5-second samples" : "Energy counters unavailable · showing CPU activity"
        }
    }
}

private struct EnergyApplication: Sendable { let path: String; let name: String }
private struct EnergyProcess: Sendable {
    let app: EnergyApplication
    let counters: ProcessCounters
    static func capture(_ apps: [EnergyApplication]) -> [Int32: EnergyProcess] {
        let required = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard required > 0 else { return [:] }
        var pids = [pid_t](repeating: 0, count: min(32768, Int(required) / MemoryLayout<pid_t>.size + 256))
        let capacity = Int32(pids.count * MemoryLayout<pid_t>.size)
        let copied = pids.withUnsafeMutableBytes { proc_listpids(UInt32(PROC_ALL_PIDS), 0, $0.baseAddress, capacity) }
        guard copied > 0 else { return [:] }
        var captured: [Int32: EnergyProcess] = [:]
        for pid in pids.prefix(Int(copied) / MemoryLayout<pid_t>.size) where pid > 0 {
            var info = proc_bsdinfo()
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) == MemoryLayout<proc_bsdinfo>.size, info.pbi_uid == getuid() else { continue }
            var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
            guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { continue }
            let executable = String(cString: path)
            guard let app = apps.first(where: { executable.hasPrefix($0.path + "/") }), let counters = ProcessCounters.read(pid: pid) else { continue }
            captured[pid] = EnergyProcess(app: app, counters: counters)
        }
        return captured
    }
}
