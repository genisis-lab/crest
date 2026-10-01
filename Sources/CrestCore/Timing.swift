import Foundation

/// A countdown that survives relaunch. Wall-clock end dates keep it accurate across sleep.
public struct FocusTimer: Codable, Equatable, Sendable {
    public static let maximum: TimeInterval = 86400
    public private(set) var duration: TimeInterval = 0
    public private(set) var endsAt: Date?
    public private(set) var pausedRemaining: TimeInterval?
    public init() {}
    public var isRunning: Bool { endsAt != nil }
    public var isPaused: Bool { pausedRemaining != nil }
    public var isActive: Bool { isRunning || isPaused }
    public func remaining(at date: Date) -> TimeInterval {
        if let endsAt { return max(0, endsAt.timeIntervalSince(date)) }
        return pausedRemaining ?? 0
    }
    public func progress(at date: Date) -> Double {
        guard duration > 0, isActive else { return 0 }
        return min(1, max(0, 1 - remaining(at: date) / duration))
    }
    public func isFinished(at date: Date) -> Bool { endsAt.map { $0 <= date } ?? false }
    public mutating func start(_ seconds: TimeInterval, at date: Date) {
        guard seconds.isFinite, seconds > 0 else { return }
        duration = min(seconds, Self.maximum); endsAt = date.addingTimeInterval(duration); pausedRemaining = nil
    }
    public mutating func pause(at date: Date) {
        guard let endsAt else { return }
        pausedRemaining = max(0, endsAt.timeIntervalSince(date)); self.endsAt = nil
    }
    public mutating func resume(at date: Date) {
        guard let pausedRemaining else { return }
        endsAt = date.addingTimeInterval(pausedRemaining); self.pausedRemaining = nil
    }
    public mutating func extend(by seconds: TimeInterval, at date: Date) {
        guard seconds.isFinite, seconds > 0, isActive else { return }
        let added = min(seconds, Self.maximum - remaining(at: date))
        guard added > 0 else { return }
        if let endsAt { self.endsAt = max(endsAt, date).addingTimeInterval(added) }
        if let pausedRemaining { self.pausedRemaining = pausedRemaining + added }
        duration = min(Self.maximum, duration + added)
    }
    public mutating func reset() { self = FocusTimer() }
}

public enum TimeFormat {
    /// Countdowns round up so "0:00" only appears once the time has passed.
    public static func string(_ seconds: TimeInterval, roundingUp: Bool = false) -> String {
        guard seconds.isFinite else { return "--:--" }
        let bounded = min(max(0, seconds), 1e9)
        let total = Int(roundingUp ? bounded.rounded(.up) : bounded.rounded(.down))
        let hours = total / 3600, minutes = total % 3600 / 60, rest = total % 60
        return hours > 0 ? String(format: "%ld:%02ld:%02ld", hours, minutes, rest) : String(format: "%ld:%02ld", minutes, rest)
    }
    /// Short form for the collapsed notch and reset times: "45s", "12m", "1h 5m", "2d 3h". Rounds up.
    public static func compact(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "—" }
        let total = Int(min(max(0, seconds), 1e9).rounded(.up))
        if total < 60 { return "\(total)s" }
        let minutes = (total + 59) / 60
        if minutes < 60 { return "\(minutes)m" }
        if minutes < 1440 { return minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(minutes % 60)m" }
        let hours = (minutes + 59) / 60
        return hours % 24 == 0 ? "\(hours / 24)d" : "\(hours / 24)d \(hours % 24)h"
    }
}

/// A player-reported position, interpolated locally between samples.
public struct PlaybackPosition: Equatable, Sendable {
    public let elapsed: Double
    public let duration: Double?
    public let rate: Double
    public let sampledAt: Date
    public init?(elapsed: Double?, duration: Double?, rate: Double, sampledAt: Date) {
        guard let elapsed, elapsed.isFinite, elapsed >= 0 else { return nil }
        self.elapsed = elapsed
        self.duration = duration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        self.rate = rate.isFinite ? max(0, rate) : 0
        self.sampledAt = sampledAt
    }
    public func elapsed(at date: Date) -> Double {
        let value = max(0, elapsed + max(0, date.timeIntervalSince(sampledAt)) * rate)
        return duration.map { min($0, value) } ?? value
    }
    public func fraction(at date: Date) -> Double? { duration.map { min(1, elapsed(at: date) / $0) } }
}
