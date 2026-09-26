import AppKit
import Foundation
import CrestCore

@MainActor final class AgentService: ObservableObject {
    @Published var sessions: [AgentSession] = []
    @Published var codex: QuotaSnapshot?
    @Published var claude: QuotaSnapshot?
    @Published var status = "Connect Codex in Settings. Claude connects through the local bridge."
    @Published var connected = false
    var onAttention: ((String) -> Void)?
    private var process: Process?
    private var input: FileHandle?
    private var buffer = Data()
    private var timer: Timer?
    private var pollTimer: Timer?
    private var lastRefresh = Date.distantPast
    private var lastSent = Date.distantPast
    private var requestID = 10
    private var pendingQuota = Set<Int>()
    private var pendingThreads = Set<Int>()
    private var shared = false
    private var eventWatcher: DispatchSourceFileSystemObject?
    private var inboxFD: Int32 = -1

    init() {
        try? CrestPaths.prepare(CrestPaths.inbox)
        drainInbox()
        inboxFD = open(CrestPaths.inbox.path, O_EVTONLY)
        if inboxFD >= 0 {
            let watcher = DispatchSource.makeFileSystemObjectSource(fileDescriptor: inboxFD, eventMask: [.write, .rename], queue: .main)
            watcher.setEventHandler { [weak self] in self?.drainInbox() }
            watcher.setCancelHandler { [fd = inboxFD] in close(fd) }
            watcher.resume(); eventWatcher = watcher
        }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.drainInbox()
                self?.sessions.removeAll { Date().timeIntervalSince($0.timestamp) > 86400 }
            }
        }
    }
    func drainInbox() {
        let files = (try? FileManager.default.contentsOfDirectory(at: CrestPaths.inbox, includingPropertiesForKeys: [.fileSizeKey, .isSymbolicLinkKey])) ?? []
        let events = files.filter { $0.pathExtension == "json" }.compactMap { url -> (URL, BridgeEvent)? in
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey]), values.isSymbolicLink != true, (values.fileSize ?? 0) <= 65536,
                  let data = try? Data(contentsOf: url), let event = try? JSONDecoder().decode(BridgeEvent.self, from: data) else { return nil }
            return (url, event)
        }.sorted { $0.1.timestamp < $1.1.timestamp }
        for (url, event) in events {
            if abs(event.timestamp.timeIntervalSinceNow) < 86400 { ingest(event) }
            try? FileManager.default.removeItem(at: url)
        }
    }
    func ingest(_ event: BridgeEvent) {
        if let quota = event.quota {
            if event.provider == "Claude", quota.receivedAt >= (claude?.receivedAt ?? .distantPast) { claude = quota }
        }
        guard event.nextState != nil else { return }
        let id = event.provider + ":" + event.sessionID
        let previous = sessions.first { $0.id == id }
        guard event.timestamp >= (previous?.timestamp ?? .distantPast) else { return }
        let session = AgentSession(event, previous: previous)
        sessions.removeAll { $0.id == id }
        if session.state != "Ended" { sessions.append(session) }
        sessions.sort { ($0.state == "Needs you" ? 1 : 0, $0.timestamp) > ($1.state == "Needs you" ? 1 : 0, $1.timestamp) }
        if session.state == "Needs you", previous?.state != "Needs you" { onAttention?("\(event.provider) needs you") }
    }
    static func findCodex() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [home + "/.local/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex", "/Applications/Codex.app/Contents/Resources/codex"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }
    func connect(path: String, socket: String = "") {
        disconnect()
        guard FileManager.default.isExecutableFile(atPath: path) else { status = "Choose a working Codex executable in Settings."; return }
        let p = Process(); let stdout = Pipe(); let stdin = Pipe()
        shared = !socket.isEmpty
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = shared ? ["app-server", "proxy", "--sock", socket] : ["app-server", "--listen", "stdio://"]
        p.standardInput = stdin; p.standardOutput = stdout; p.standardError = FileHandle.nullDevice
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            if chunk.isEmpty { handle.readabilityHandler = nil; return }
            Task { @MainActor in self?.receive(chunk) }
        }
        p.terminationHandler = { [weak self] ended in
            Task { @MainActor in
                guard self?.process === ended else { return }
                self?.connected = false; self?.status = "Codex disconnected. Reconnect in Settings."; self?.pollTimer?.invalidate()
            }
        }
        do {
            try p.run(); process = p; input = stdin.fileHandleForWriting; status = "Connecting to Codex…"
            send(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "crest", "title": "Crest", "version": "0.1.0"], "capabilities": ["experimentalApi": true]]])
            pollTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    if !self.connected { self.status = "Codex did not complete its handshake. Reconnect or check the executable."; return }
                    if Date().timeIntervalSince(self.lastSent) > 300 { self.refresh() }
                    if self.shared { self.readThreads() }
                }
            }
        } catch { status = "Could not launch Codex: \(error.localizedDescription)" }
    }
    func disconnect() {
        pollTimer?.invalidate(); pollTimer = nil
        let old = process; process = nil
        try? input?.close(); input = nil
        if old?.isRunning == true { old?.terminate() }
        connected = false; buffer.removeAll(); pendingQuota.removeAll(); pendingThreads.removeAll()
        sessions.removeAll { $0.provider == "Codex" }; status = "Codex disconnected."
    }
    func refresh() {
        guard connected else { return }
        requestID += 1; pendingQuota.insert(requestID); lastSent = Date()
        send(["id": requestID, "method": "account/rateLimits/read"])
    }
    private func readThreads() {
        guard pendingThreads.isEmpty else { return }
        requestID += 1; pendingThreads.insert(requestID)
        send(["id": requestID, "method": "thread/list", "params": ["limit": 50, "sortKey": "updated_at", "archived": false]])
    }
    private func send(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message) else { return }
        do { try input?.write(contentsOf: data + Data([10])) } catch { status = "Codex connection closed." }
    }
    private func receive(_ data: Data) {
        buffer.append(data)
        if buffer.count > 8_000_000 { buffer.removeAll(); status = "Codex sent an oversized message."; return }
        while let end = buffer.firstIndex(of: 10) {
            let line = buffer.prefix(upTo: end); buffer.removeSubrange(...end)
            guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            if let id = message["id"] as? Int, let error = message["error"] as? [String: Any] {
                pendingQuota.remove(id); pendingThreads.remove(id)
                status = error["message"] as? String ?? "Codex request failed."; continue
            }
            if message["id"] as? Int == 1 {
                connected = true; status = shared ? "Connected to the selected Codex server" : "Usage connected · session alerts require a shared server"
                send(["method": "initialized"]); refresh(); if shared { readThreads() }; continue
            }
            if let id = message["id"] as? Int, pendingQuota.remove(id) != nil, let result = message["result"] as? [String: Any] {
                codex = QuotaSnapshot.codex(result); lastRefresh = Date()
                status = codex?.windows.isEmpty == false ? (shared ? "Usage and shared-session monitoring connected" : "Usage connected · standalone sessions are not monitored") : "Connected, but this account returned no quota windows."
            }
            if let id = message["id"] as? Int, pendingThreads.remove(id) != nil, let result = message["result"] as? [String: Any], let threads = result["data"] as? [[String: Any]] {
                for thread in threads {
                    guard let threadID = thread["id"] as? String, let state = thread["status"] as? [String: Any] else { continue }
                    handleThread(threadID, state: state, project: (thread["cwd"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent })
                }
            }
            let method = message["method"] as? String; let params = message["params"] as? [String: Any] ?? [:]
            if method == "account/rateLimits/updated" { codex = QuotaSnapshot.codex(params) }
            if method == "thread/status/changed", let id = params["threadId"] as? String, let state = params["status"] as? [String: Any] { handleThread(id, state: state, project: nil) }
            // This observer never responds to approval requests or starts/resumes a turn.
        }
    }
    private func handleThread(_ id: String, state: [String: Any], project: String?) {
        let flags = state["activeFlags"] as? [String] ?? []
        let name = flags.first { ["waitingOnApproval", "waitingOnUserInput"].contains($0) } ?? state["type"] as? String ?? ""
        guard ["active", "idle", "waitingOnApproval", "waitingOnUserInput"].contains(name) else { return }
        ingest(BridgeEvent(provider: "Codex", sessionID: id, event: name, project: project))
    }
    func reveal(_ session: AgentSession) {
        if session.provider == "Codex", let uuid = UUID(uuidString: session.sessionID), let url = URL(string: "codex://threads/\(uuid.uuidString.lowercased())") {
            if NSWorkspace.shared.open(url) { return }
        }
        if let tty = session.tty, tty.range(of: #"^/dev/tty[a-zA-Z0-9]+$"#, options: .regularExpression) != nil, session.terminal == "Apple_Terminal" {
            let script = "tell application \"Terminal\"\nactivate\nrepeat with w in windows\nrepeat with t in tabs of w\nif tty of t is \"\(tty)\" then\nset selected tab of w to t\nset index of w to 1\nreturn\nend if\nend repeat\nend repeat\nend tell"
            var error: NSDictionary?; NSAppleScript(source: script)?.executeAndReturnError(&error)
            if error == nil { return }
        }
        let bundle = session.terminal == "iTerm.app" ? "com.googlecode.iterm2" : session.terminal == "Apple_Terminal" ? "com.apple.Terminal" : session.provider == "Codex" ? "com.openai.codex" : nil
        guard let bundle, let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { status = "Exact session routing is unavailable for this terminal."; return }
        NSWorkspace.shared.openApplication(at: app, configuration: .init())
        status = "Opened the application; exact tab routing was unavailable."
    }
}

enum ClaudeSetup {
    static var settings: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json") }
    static var bridge: URL { CrestPaths.root.appendingPathComponent("bin/crest-bridge") }
    static func install(includeStatus: Bool) throws -> String {
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/crest-bridge")
        guard FileManager.default.fileExists(atPath: bundled.path) else { throw NSError(domain: "Crest", code: 1, userInfo: [NSLocalizedDescriptionKey: "Run the bundled Crest.app to install its bridge."]) }
        try CrestPaths.prepare(bridge.deletingLastPathComponent())
        let helper = try Data(contentsOf: bundled); try CrestPaths.save(helper, to: bridge)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: bridge.path)
        let data = FileManager.default.fileExists(atPath: settings.path) ? try Data(contentsOf: settings) : nil
        let original: [String: Any]
        if let data {
            guard let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any], decoded["hooks"] == nil || decoded["hooks"] is [String: [[String: Any]]] else {
                throw NSError(domain: "Crest", code: 2, userInfo: [NSLocalizedDescriptionKey: "Claude settings have an unsupported structure. The file was not changed."])
            }
            original = decoded
        } else { original = [:] }
        if let data { try CrestPaths.save(data, to: CrestPaths.root.appendingPathComponent("claude-settings-backup-\(Int(Date().timeIntervalSince1970)).json")) }
        var updated = HookConfiguration.merge(original, bridgePath: bridge.path)
        let ownCommand = HookConfiguration.quote(bridge.path) + " statusline"
        if includeStatus {
            if (original["statusLine"] as? [String: Any])?["command"] as? String != ownCommand {
                let previousFile = CrestPaths.root.appendingPathComponent("previous-statusline.json")
                if let previous = original["statusLine"] as? [String: Any] {
                    try CrestPaths.save(JSONSerialization.data(withJSONObject: previous), to: previousFile)
                } else if FileManager.default.fileExists(atPath: previousFile.path) {
                    try FileManager.default.removeItem(at: previousFile)
                }
            }
            updated["statusLine"] = ["type": "command", "command": ownCommand]
        }
        try CrestPaths.save(JSONSerialization.data(withJSONObject: updated, options: [.prettyPrinted, .sortedKeys]), to: settings)
        return "Bridge installed. Restart Claude Code sessions. Usage needs Claude Code 2.1.251+ and an eligible account."
    }
    static func uninstall() throws -> String {
        let data = try Data(contentsOf: settings)
        guard let original = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "Crest", code: 2, userInfo: [NSLocalizedDescriptionKey: "Claude settings are not a JSON object. The file was not changed."])
        }
        var updated = HookConfiguration.remove(original, bridgePath: bridge.path)
        if (updated["statusLine"] as? [String: Any])?["command"] as? String == HookConfiguration.quote(bridge.path) + " statusline" {
            if let previous = try? Data(contentsOf: CrestPaths.root.appendingPathComponent("previous-statusline.json")), let value = try? JSONSerialization.jsonObject(with: previous) { updated["statusLine"] = value }
            else { updated.removeValue(forKey: "statusLine") }
        }
        try CrestPaths.save(JSONSerialization.data(withJSONObject: updated, options: [.prettyPrinted, .sortedKeys]), to: settings)
        return "Crest hooks removed. Other Claude settings preserved."
    }
}
