import Foundation
import CryptoKit

public enum CrestPaths {
    public static var root: URL {
        #if DEBUG
        if let test = ProcessInfo.processInfo.environment["CREST_TEST_DATA_DIR"], test.hasPrefix("/") { return URL(fileURLWithPath: test, isDirectory: true) }
        #endif
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Crest", isDirectory: true)
    }
    public static var inbox: URL { root.appendingPathComponent("Events", isDirectory: true) }
    public static func prepare(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
    public static func save(_ data: Data, to url: URL) throws {
        try prepare(url.deletingLastPathComponent())
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

public struct QuotaWindow: Codable, Identifiable, Equatable {
    public var id: String
    public var label: String
    public var used: Double
    public var reset: Date?
    public var remaining: Double { max(0, 100 - used) }
    public init(id: String, label: String, used: Double, reset: Date?) { self.id = id; self.label = label; self.used = used; self.reset = reset }
}
public struct QuotaSnapshot: Codable, Equatable {
    public var provider: String
    public var windows: [QuotaWindow]
    public var receivedAt: Date
    public var plan: String?
    public init(provider: String, windows: [QuotaWindow], receivedAt: Date = Date(), plan: String? = nil) {
        self.provider = provider; self.windows = windows; self.receivedAt = receivedAt; self.plan = plan
    }
    public var stale: Bool { Date().timeIntervalSince(receivedAt) > 600 }
    public static func codex(_ result: [String: Any], now: Date = Date()) -> QuotaSnapshot {
        let buckets = result["rateLimitsByLimitId"] as? [String: [String: Any]]
        let fallback = result["rateLimits"] as? [String: Any]
        let sources = (buckets?.isEmpty == false ? buckets : nil) ?? fallback.map { ["default": $0] } ?? [:]
        var windows: [QuotaWindow] = []; var plan: String?
        for key in sources.keys.sorted() {
            guard let bucket = sources[key] else { continue }
            plan = plan ?? bucket["planType"] as? String
            for slot in ["primary", "secondary"] {
                guard let value = bucket[slot] as? [String: Any], let percent = value["usedPercent"] as? Double, percent.isFinite, percent >= 0 else { continue }
                let minutes = (value["windowDurationMins"] as? NSNumber)?.intValue
                let duration = minutes.map { $0 % 1440 == 0 ? "\($0 / 1440) days" : $0 % 60 == 0 ? "\($0 / 60) hours" : "\($0) minutes" } ?? slot.capitalized
                windows.append(QuotaWindow(id: "\(key).\(slot)", label: (sources.count > 1 ? "\(bucket["limitName"] as? String ?? key) · " : "") + duration, used: percent, reset: (value["resetsAt"] as? Double).map(Date.init(timeIntervalSince1970:))))
            }
        }
        return QuotaSnapshot(provider: "Codex", windows: windows, receivedAt: now, plan: plan)
    }
    public static func claude(_ input: [String: Any], now: Date = Date()) -> QuotaSnapshot {
        let rate = input["rate_limits"] as? [String: [String: Any]] ?? [:]
        let windows = [("five_hour", "5 hours"), ("seven_day", "7 days"), ("spend_limit", "Spend limit")].compactMap { key, label -> QuotaWindow? in
            guard let value = rate[key], let used = value["used_percentage"] as? Double, used.isFinite, used >= 0 else { return nil }
            let reset = (value["resets_at"] as? Double).map(Date.init(timeIntervalSince1970:))
            if let reset, reset <= now { return nil }
            return QuotaWindow(id: key, label: label, used: used, reset: reset)
        }
        return QuotaSnapshot(provider: "Claude", windows: windows, receivedAt: now)
    }
}

public struct BridgeEvent: Codable {
    public var provider: String
    public var sessionID: String
    public var event: String
    public var notificationType: String?
    public var project: String?
    public var terminal: String?
    public var tty: String?
    public var terminalSession: String?
    public var timestamp: Date
    public var quota: QuotaSnapshot?
    public init(provider: String, sessionID: String, event: String, notificationType: String? = nil, project: String? = nil, terminal: String? = nil, tty: String? = nil, terminalSession: String? = nil, timestamp: Date = Date(), quota: QuotaSnapshot? = nil) {
        self.provider = provider; self.sessionID = sessionID; self.event = event; self.notificationType = notificationType; self.project = project; self.terminal = terminal; self.tty = tty; self.terminalSession = terminalSession; self.timestamp = timestamp; self.quota = quota
    }
    public var nextState: String? {
        switch event {
        case "PermissionRequest", "waitingOnApproval", "waitingOnUserInput": return "Needs you"
        case "Notification": return ["permission_prompt", "elicitation_dialog", "agent_needs_input", "worker_permission_prompt"].contains(notificationType ?? "") ? "Needs you" : nil
        case "SessionEnd": return "Ended"
        case "Stop", "task_complete", "idle": return "Done"
        case "SessionStart", "UserPromptSubmit", "PostToolUse", "PostToolUseFailure", "task_started", "active": return "Working"
        default: return nil
        }
    }
}
public struct AgentSession: Identifiable {
    public var id: String { provider + ":" + sessionID }
    public var provider: String
    public var sessionID: String
    public var project: String
    public var state: String
    public var timestamp: Date
    public var terminal: String?
    public var tty: String?
    public var terminalSession: String?
    public init(_ event: BridgeEvent, previous: AgentSession? = nil) {
        provider = event.provider; sessionID = event.sessionID; project = event.project ?? previous?.project ?? "Local session"
        state = event.nextState ?? previous?.state ?? "Connected"; timestamp = event.timestamp
        terminal = event.terminal ?? previous?.terminal; tty = event.tty ?? previous?.tty; terminalSession = event.terminalSession ?? previous?.terminalSession
    }
}

public struct ClipItem: Codable, Identifiable, Equatable {
    public var id: UUID
    public var text: String?
    public var image: Data?
    public var created: Date
    public var pinned: Bool
    public init(text: String? = nil, image: Data? = nil, created: Date = Date(), pinned: Bool = false) { id = UUID(); self.text = text; self.image = image; self.created = created; self.pinned = pinned }
    public static func retained(_ items: [ClipItem], days: Int, now: Date = Date()) -> [ClipItem] {
        items.filter { $0.pinned || now.timeIntervalSince($0.created) < Double(max(1, min(365, days))) * 86400 }
    }
}
public enum ClipboardPolicy {
    public static func shouldCapture(bundle: String?, types: [String], exclusions: [String]) -> Bool {
        let sensitive = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType", "com.agilebits.onepassword"]
        if types.contains(where: { sensitive.contains($0) }) { return false }
        guard let bundle else { return false }
        let lower = bundle.lowercased()
        let passwordManagers = ["1password", "onepassword", "agilebits", "bitwarden", "lastpass", "keepass", "strongbox", "dashlane", "enpass", "protonpass", "com.apple.passwords", "com.apple.keychainaccess"]
        return !passwordManagers.contains(where: lower.contains) && !exclusions.contains(where: { $0.lowercased() == lower })
    }
}
public struct HardwareKey {
    public let code: Int
    public let down: Bool
    public let repeated: Bool
    public init?(data1: Int) {
        let code = (data1 >> 16) & 0xffff
        let state = (data1 >> 8) & 0xff
        guard [0, 1, 2, 3, 7].contains(code), state == 0x0a || state == 0x0b else { return nil }
        self.code = code; self.down = state == 0x0a; self.repeated = (data1 & 1) != 0
    }
}
public enum EncryptedArchive {
    public static func seal(_ data: Data, key: SymmetricKey) throws -> Data { try AES.GCM.seal(data, using: key).combined! }
    public static func open(_ data: Data, key: SymmetricKey) throws -> Data { try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key) }
}

public enum HookConfiguration {
    public static let events = ["SessionStart", "UserPromptSubmit", "PermissionRequest", "Notification", "PostToolUse", "PostToolUseFailure", "Stop", "SessionEnd"]
    public static func quote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    public static func merge(_ original: [String: Any], bridgePath: String) -> [String: Any] {
        var result = remove(original, bridgePath: bridgePath)
        var hooks = result["hooks"] as? [String: [[String: Any]]] ?? [:]
        for name in events {
            var entries = hooks[name] ?? []
            entries.append(["hooks": [["type": "command", "command": quote(bridgePath) + " hook", "timeout": 3]]])
            hooks[name] = entries
        }
        result["hooks"] = hooks; return result
    }
    public static func remove(_ original: [String: Any], bridgePath: String) -> [String: Any] {
        var result = original
        guard var hooks = result["hooks"] as? [String: [[String: Any]]] else { return result }
        for name in events {
            hooks[name] = (hooks[name] ?? []).compactMap { entry in
                var entry = entry
                let commands = (entry["hooks"] as? [[String: Any]] ?? []).filter { ($0["command"] as? String) != quote(bridgePath) + " hook" }
                if commands.isEmpty { return nil }; entry["hooks"] = commands; return entry
            }
        }
        result["hooks"] = hooks; return result
    }
}
