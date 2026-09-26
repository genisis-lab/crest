import Foundation
import Darwin

public struct ProcessCounters: Sendable {
    public let started: UInt64
    public let cpuNanoseconds: UInt64
    public let energyNanojoules: UInt64?
    public init(started: UInt64, cpuNanoseconds: UInt64, energyNanojoules: UInt64?) {
        self.started = started; self.cpuNanoseconds = cpuNanoseconds; self.energyNanojoules = energyNanojoules
    }
    public static func read(pid: Int32) -> ProcessCounters? {
        var usage = rusage_info_v6()
        let result = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V6, $0) }
        }
        if result == 0 {
            return ProcessCounters(started: usage.ri_proc_start_abstime, cpuNanoseconds: usage.ri_user_time &+ usage.ri_system_time,
                energyNanojoules: usage.ri_energy_nj > 0 ? usage.ri_energy_nj : nil)
        }
        var fallback = rusage_info_v0()
        let fallbackResult = withUnsafeMutablePointer(to: &fallback) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V0, $0) }
        }
        guard fallbackResult == 0 else { return nil }
        return ProcessCounters(started: fallback.ri_proc_start_abstime, cpuNanoseconds: fallback.ri_user_time &+ fallback.ri_system_time, energyNanojoules: nil)
    }
}

public struct ProcessActivity: Sendable {
    public let cpuPercent: Double
    public let watts: Double?
    public init?(previous: ProcessCounters, current: ProcessCounters, elapsed: TimeInterval) {
        guard elapsed.isFinite, elapsed > 0, elapsed <= 60, previous.started == current.started, current.cpuNanoseconds >= previous.cpuNanoseconds else { return nil }
        cpuPercent = Double(current.cpuNanoseconds - previous.cpuNanoseconds) / elapsed / 10_000_000
        if let old = previous.energyNanojoules, let new = current.energyNanojoules, new >= old {
            watts = Double(new - old) / elapsed / 1_000_000_000
        } else { watts = nil }
    }
}
