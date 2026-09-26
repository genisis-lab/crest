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
    ("Hook merge and uninstall", hookInstallationIsIdempotentAndRemovalPreservesOthers)
]
for (name, test) in tests { let before = failures; do { try test() } catch { failures += 1; print("FAIL \(name): \(error)") }; if failures == before { print("PASS \(name)") } }
print("\(tests.count) checks, \(assertions) assertions, \(failures) failures")
exit(failures == 0 ? 0 : 1)
