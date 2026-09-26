import Darwin
import Foundation
import CryptoKit
import CrestCore

func codexUsesBucketsRatherThanDuplicatingLegacyLimits() {
    let result: [String: Any] = ["rateLimits": ["primary": ["usedPercent": 99.0]], "rateLimitsByLimitId": ["codex": ["planType": "pro", "primary": ["usedPercent": 25.0, "windowDurationMins": 300, "resetsAt": 2_000_000_000.0]], "review": ["secondary": ["usedPercent": 8.0, "windowDurationMins": 10080]]]]
    let snapshot = QuotaSnapshot.codex(result)
    check(snapshot.windows.count == 2)
    check(snapshot.windows.first?.remaining == 75)
    check(snapshot.windows.first?.label == "codex · 5 hours")
    check(snapshot.windows.last?.label == "review · 7 days")
    check(snapshot.plan == "pro")
}
func quotaNullsAreUnavailableNotZero() {
    check(QuotaSnapshot.codex([:]).windows.isEmpty)
    check(QuotaSnapshot.codex(["rateLimits": ["primary": ["usedPercent": NSNull()]]]).windows.isEmpty)
    check(QuotaSnapshot.codex(["rateLimits": ["primary": ["usedPercent": -5.0]]]).windows.isEmpty)
    check(QuotaSnapshot.codex(["rateLimits": ["primary": ["usedPercent": Double.nan]]]).windows.isEmpty)
}
func legacyCodexAndOverLimitAreSupported() {
    let snapshot = QuotaSnapshot.codex(["rateLimits": ["primary": ["usedPercent": 120.0, "windowDurationMins": 60]]])
    check(snapshot.windows.first?.remaining == 0)
    check(snapshot.windows.first?.used == 120)
}
func claudeDiscardsExpiredWindowsAndKeepsIndependentWindows() {
    let now = Date(timeIntervalSince1970: 1000)
    let snapshot = QuotaSnapshot.claude(["rate_limits": ["five_hour": ["used_percentage": 10.0, "resets_at": 900.0], "seven_day": ["used_percentage": 40.0, "resets_at": 2000.0], "spend_limit": ["used_percentage": 105.0]]], now: now)
    check(snapshot.windows.map(\.id) == ["seven_day", "spend_limit"])
    check(snapshot.windows.last?.remaining == 0)
    check(QuotaSnapshot.claude([:]).windows.isEmpty)
}
func passiveNotificationsDoNotClaimAnApproval() {
    let idle = BridgeEvent(provider: "Claude", sessionID: "a", event: "Notification", notificationType: "idle_prompt")
    check(idle.nextState == nil)
    let waiting = BridgeEvent(provider: "Claude", sessionID: "a", event: "PermissionRequest")
    check(waiting.nextState == "Needs you")
    let resolved = BridgeEvent(provider: "Claude", sessionID: "a", event: "PostToolUse")
    check(resolved.nextState == "Working")
}
func sessionUpdatesPreserveRoutingAndProviderIdentity() {
    let event = BridgeEvent(provider: "Claude", sessionID: "a", event: "SessionStart", project: "Project", terminal: "Apple_Terminal", tty: "/dev/ttys001")
    let session = AgentSession(BridgeEvent(provider: "Claude", sessionID: "a", event: "PermissionRequest"), previous: AgentSession(event))
    check(session.tty == "/dev/ttys001")
    check(session.project == "Project")
    check(session.id == "Claude:a")
}
func retentionNeverDeletesPins() {
    let now = Date(timeIntervalSince1970: 10_000_000)
    let old = now.addingTimeInterval(-86400 * 10)
    let items = [ClipItem(text: "old", created: old), ClipItem(text: "pinned", created: old, pinned: true), ClipItem(text: "recent", created: now)]
    check(ClipItem.retained(items, days: 7, now: now).compactMap(\.text) == ["pinned", "recent"])
}
func clipboardExclusionsApplyBeforeCapture() {
    check(!ClipboardPolicy.shouldCapture(bundle: "com.agilebits.onepassword7", types: [], exclusions: []))
    check(!ClipboardPolicy.shouldCapture(bundle: "com.apple.Safari", types: ["org.nspasteboard.ConcealedType"], exclusions: []))
    check(!ClipboardPolicy.shouldCapture(bundle: "com.example.private", types: [], exclusions: ["com.example.private"]))
    check(!ClipboardPolicy.shouldCapture(bundle: nil, types: [], exclusions: []))
    check(ClipboardPolicy.shouldCapture(bundle: "com.apple.TextEdit", types: ["public.utf8-plain-text"], exclusions: []))
}
func encryptionDetectsTamperingAndWrongKeys() throws {
    let key = SymmetricKey(size: .bits256), data = Data("private text".utf8)
    let sealed = try EncryptedArchive.seal(data, key: key)
    check(sealed != data)
    check(try EncryptedArchive.open(sealed, key: key) == data)
    check(throws: (any Error).self) { try EncryptedArchive.open(sealed, key: SymmetricKey(size: .bits256)) }
    var tampered = sealed; tampered[tampered.count - 1] ^= 1
    check(throws: (any Error).self) { try EncryptedArchive.open(tampered, key: key) }
}
func hookInstallationIsIdempotentAndRemovalPreservesOthers() throws {
    let existing: [String: Any] = ["permissions": ["allow": ["Read"]], "statusLine": ["type": "command", "command": "my-status"], "hooks": ["Stop": [["hooks": [["type": "command", "command": "my-hook"]]]]]]
    let path = "/a space/crest-bridge"
    let once = HookConfiguration.merge(existing, bridgePath: path)
    let twice = HookConfiguration.merge(once, bridgePath: path)
    let encode: ([String: Any]) throws -> Data = { try JSONSerialization.data(withJSONObject: $0, options: .sortedKeys) }
    check(try encode(once) == encode(twice))
    let removed = HookConfiguration.remove(twice, bridgePath: path)
    let hooks = removed["hooks"] as? [String: [[String: Any]]]
    check(hooks?["Stop"]?.count == 1)
    check((removed["statusLine"] as? [String: String])?["command"] == "my-status")
    check(removed["permissions"] != nil)
}
func hardwareKeysIgnoreUnrelatedEvents() {
    check(HardwareKey(data1: (0 << 16) | (0x0a << 8))?.down == true)
    check(HardwareKey(data1: (1 << 16) | (0x0b << 8))?.down == false)
    check(HardwareKey(data1: (2 << 16) | (0x0a << 8) | 1)?.repeated == true)
    check(HardwareKey(data1: (7 << 16) | (0x0a << 8))?.code == 7)
    check(HardwareKey(data1: (16 << 16) | (0x0a << 8)) == nil)
    check(HardwareKey(data1: (0 << 16) | (0x02 << 8)) == nil)
}

func quotaFreshnessHandlesOfflineAndClockChanges() {
    let now = Date(timeIntervalSince1970: 10000)
    check(!QuotaSnapshot(provider: "Codex", windows: [], receivedAt: now.addingTimeInterval(-599)).isStale(at: now))
    check(QuotaSnapshot(provider: "Codex", windows: [], receivedAt: now.addingTimeInterval(-601)).isStale(at: now))
    check(QuotaSnapshot(provider: "Codex", windows: [], receivedAt: now.addingTimeInterval(120)).isStale(at: now))
}
func clipboardArchiveMigrationPreservesItemsAndRejectsNewerFormats() throws {
    let clips = [ClipItem(text: "migration fixture", pinned: true)]
    check(try ClipboardArchive.decode(JSONEncoder().encode(clips)) == clips)
    check(try ClipboardArchive.decode(ClipboardArchive.encode(clips)) == clips)
    check(throws: (any Error).self) { try ClipboardArchive.decode(Data(#"{"version":99,"items":[]}"#.utf8)) }
    check(throws: (any Error).self) { try ClipboardArchive.decode(Data("broken".utf8)) }
}


func downloadPackagesExcludeMetadataAndSymlinks() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let package = directory.appendingPathComponent("Fixture.bin.download")
    try FileManager.default.createDirectory(at: package, withIntermediateDirectories: false)
    try Data(repeating: 1, count: 250).write(to: package.appendingPathComponent("Fixture.bin"))
    try PropertyListSerialization.data(fromPropertyList: ["DownloadEntryProgressTotalToLoad": 1000], format: .binary, options: 0).write(to: package.appendingPathComponent("Info.plist"))
    try Data(repeating: 2, count: 500).write(to: package.appendingPathComponent("ResumeData"))
    let outside = directory.appendingPathComponent("private.txt")
    try Data(repeating: 3, count: 9000).write(to: outside)
    try FileManager.default.createSymbolicLink(at: package.appendingPathComponent("linked.txt"), withDestinationURL: outside)
    let result = DownloadInspection.size(at: package)
    check(result?.bytes == 250)
    check(result?.fraction == 0.25)
    let partial = directory.appendingPathComponent("file.crdownload")
    try Data(repeating: 1, count: 42).write(to: partial)
    check(DownloadInspection.size(at: partial)?.bytes == 42)
    check(DownloadInspection.size(at: partial)?.fraction == nil)
    check(DownloadSize(bytes: 120, expected: 100).fraction == nil)
    check(DownloadSize(bytes: 0, expected: -1).fraction == nil)
    try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("secret.part"), withDestinationURL: outside)
    check(DownloadInspection.size(at: directory.appendingPathComponent("secret.part")) == nil)
}
func processCountersHandleUnitsResetsAndPIDReuse() {
    let previous = ProcessCounters(started: 1, cpuNanoseconds: 1_000_000_000, energyNanojoules: 2_000_000_000)
    let current = ProcessCounters(started: 1, cpuNanoseconds: 2_000_000_000, energyNanojoules: 12_000_000_000)
    let delta = ProcessActivity(previous: previous, current: current, elapsed: 5)
    check(delta?.cpuPercent == 20)
    check(delta?.watts == 2)
    check(ProcessActivity(previous: previous, current: current, elapsed: 0) == nil)
    check(ProcessActivity(previous: previous, current: current, elapsed: 120) == nil)
    check(ProcessActivity(previous: previous, current: ProcessCounters(started: 2, cpuNanoseconds: 4_000_000_000, energyNanojoules: 10), elapsed: 5) == nil)
    check(ProcessActivity(previous: current, current: previous, elapsed: 5) == nil)
    check(ProcessActivity(previous: previous, current: ProcessCounters(started: 1, cpuNanoseconds: 2_000_000_000, energyNanojoules: nil), elapsed: 5)?.watts == nil)
    check(ProcessCounters.read(pid: getpid()) != nil)
}
func diagnosticsUseOnlyExplicitFields() throws {
    let report = DiagnosticsReport(appVersion: "0.3.0", build: "3", osVersion: "macOS", architecture: "Apple Silicon", displayCount: 1, hasNotchedDisplay: true,
        features: ["codexConnected": true, "clipboard_secret_marker": true])
    let data = try report.data()
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    check(Set(json.keys) == Set(["schemaVersion", "appVersion", "build", "osVersion", "architecture", "displayCount", "hasNotchedDisplay", "features"]))
    check((json["features"] as? [String: Bool]) == ["codexConnected": true])
    check(!String(decoding: data, as: UTF8.self).contains("secret_marker"))
}
func clipboardFailuresPreserveExistingArchive() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("history.aesgcm")
    let key = SymmetricKey(size: .bits256)
    let original = try EncryptedArchive.seal(ClipboardArchive.encode([ClipItem(text: "fixture", pinned: true)]), key: key)
    try CrestPaths.save(original, to: file)
    var mayCreate = true
    let loaded = try ClipboardStore.load(from: file) { create in mayCreate = create; return key }
    check(!mayCreate)
    check(loaded.1.first?.pinned == true)
    check(throws: (any Error).self) { try ClipboardStore.load(from: file) { _ in throw CocoaError(.fileReadNoPermission) } }
    check(try Data(contentsOf: file) == original)
    check(throws: (any Error).self) { try ClipboardStore.load(from: file) { _ in SymmetricKey(size: .bits256) } }
    check(try Data(contentsOf: file) == original)
    try Data("corrupt".utf8).write(to: file)
    check(throws: (any Error).self) { try ClipboardStore.load(from: file) { create in check(!create); return key } }
    check(try Data(contentsOf: file) == Data("corrupt".utf8))
    var askedForKey = false
    check(throws: (any Error).self) { try ClipboardStore.load(from: directory) { _ in askedForKey = true; return key } }
    check(!askedForKey)
    let new = try ClipboardStore.load(from: directory.appendingPathComponent("new.aesgcm")) { create in check(create); return key }
    check(new.1.isEmpty)
}

func concurrentSessionsRejectDelayedEvents() {
    var ledger = SessionLedger()
    func event(_ id: String, _ name: String, _ timestamp: Double, provider: String = "Claude") -> BridgeEvent {
        BridgeEvent(provider: provider, sessionID: id, event: name, tty: "/dev/ttys001", timestamp: Date(timeIntervalSince1970: timestamp))
    }
    check(!ledger.apply(event("one", "SessionStart", 10)))
    check(!ledger.apply(event("two", "SessionStart", 11)))
    check(ledger.apply(event("one", "PermissionRequest", 12)))
    check(!ledger.apply(event("one", "PermissionRequest", 13)))
    check(ledger.sessions.first?.sessionID == "one")
    check(ledger.sessions.count == 2)
    check(!ledger.apply(event("one", "PostToolUse", 14)))
    check(ledger.sessions.first { $0.sessionID == "one" }?.state == "Working")
    ledger.apply(event("one", "SessionEnd", 16))
    ledger.apply(event("one", "PermissionRequest", 15))
    check(!ledger.sessions.contains { $0.sessionID == "one" })
    ledger.apply(event("two", "waitingOnApproval", 17, provider: "Codex"))
    check(ledger.sessions.count == 2)
    ledger.remove(provider: "Codex")
    check(ledger.sessions.count == 1 && ledger.sessions[0].provider == "Claude")
    ledger.prune(at: Date(timeIntervalSince1970: 100000))
    check(ledger.sessions.isEmpty)
}

private var failures = 0
private var assertions = 0
func check(_ condition: @autoclosure () throws -> Bool, file: String = #filePath, line: Int = #line) {
    assertions += 1
    do { if try !condition() { failures += 1; print("FAIL \(URL(fileURLWithPath: file).lastPathComponent):\(line)") } }
    catch { failures += 1; print("FAIL unexpected error at line \(line): \(error)") }
}
func check<T>(throws: (any Error).Type, _ body: () throws -> T, line: Int = #line) {
    assertions += 1
    do { _ = try body(); failures += 1; print("FAIL expected an error at line \(line)") } catch {}
}
let tests: [(String, () throws -> Void)] = [
    ("Codex bucket mapping", codexUsesBucketsRatherThanDuplicatingLegacyLimits),
    ("Missing quota", quotaNullsAreUnavailableNotZero),
    ("Legacy and over-limit quota", legacyCodexAndOverLimitAreSupported),
    ("Claude expired windows", claudeDiscardsExpiredWindowsAndKeepsIndependentWindows),
    ("Approval lifecycle", passiveNotificationsDoNotClaimAnApproval),
    ("Session routing", sessionUpdatesPreserveRoutingAndProviderIdentity),
    ("Clipboard retention", retentionNeverDeletesPins),
    ("Clipboard exclusion", clipboardExclusionsApplyBeforeCapture),
    ("Encryption authentication", encryptionDetectsTamperingAndWrongKeys),
    ("Hook merge and uninstall", hookInstallationIsIdempotentAndRemovalPreservesOthers),
    ("Hardware key filtering", hardwareKeysIgnoreUnrelatedEvents),
    ("Quota freshness", quotaFreshnessHandlesOfflineAndClockChanges),
    ("Clipboard archive migration", clipboardArchiveMigrationPreservesItemsAndRejectsNewerFormats),
    ("Safari download packages", downloadPackagesExcludeMetadataAndSymlinks),
    ("Process energy counters", processCountersHandleUnitsResetsAndPIDReuse),
    ("Diagnostics privacy", diagnosticsUseOnlyExplicitFields),
    ("Clipboard storage recovery", clipboardFailuresPreserveExistingArchive),
    ("Concurrent session lifecycle", concurrentSessionsRejectDelayedEvents)
]
for (name, test) in tests { let before = failures; do { try test() } catch { failures += 1; print("FAIL \(name): \(error)") }; if failures == before { print("PASS \(name)") } }
print("\(tests.count) checks, \(assertions) assertions, \(failures) failures")
exit(failures == 0 ? 0 : 1)
