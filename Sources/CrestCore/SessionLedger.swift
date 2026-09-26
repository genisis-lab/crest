import Foundation

/// Keeps session transitions independent and remembers ended sessions to reject delayed events.
public struct SessionLedger {
    public private(set) var sessions: [AgentSession] = []
    private var latest: [String: Date] = [:]
    public init() {}
    @discardableResult public mutating func apply(_ event: BridgeEvent) -> Bool {
        guard event.nextState != nil else { return false }
        let id = event.provider + ":" + event.sessionID
        guard event.timestamp >= (latest[id] ?? .distantPast) else { return false }
        let previous = sessions.first { $0.id == id }
        let next = AgentSession(event, previous: previous)
        latest[id] = event.timestamp
        sessions.removeAll { $0.id == id }
        if next.state != "Ended" { sessions.append(next) }
        sessions.sort { ($0.state == "Needs you" ? 1 : 0, $0.timestamp) > ($1.state == "Needs you" ? 1 : 0, $1.timestamp) }
        return next.state == "Needs you" && previous?.state != "Needs you"
    }
    public mutating func remove(provider: String) {
        sessions.removeAll { $0.provider == provider }
        latest = latest.filter { !$0.key.hasPrefix(provider + ":") }
    }
    public mutating func prune(at date: Date = Date()) {
        latest = latest.filter { date.timeIntervalSince($0.value) < 86400 }
        sessions.removeAll { latest[$0.id] == nil }
    }
}
