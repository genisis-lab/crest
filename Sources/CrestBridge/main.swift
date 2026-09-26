import Foundation
import CrestCore
import Darwin

let mode = CommandLine.arguments.dropFirst().first ?? "hook"
let payload = FileHandle.standardInput.readDataToEndOfFile()
if payload.count <= 2_000_000, let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] {
    let env = ProcessInfo.processInfo.environment
    var tty = env["TTY"]
    if tty == nil {
        let p = Process(); let pipe = Pipe(); p.executableURL = URL(fileURLWithPath: "/bin/ps"); p.arguments = ["-o", "tty=", "-p", String(getppid())]; p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        if (try? p.run()) != nil {
            let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if text.hasPrefix("ttys") { tty = "/dev/" + text }
        }
    }
    let event = BridgeEvent(provider: "Claude", sessionID: json["session_id"] as? String ?? "unknown", event: mode == "statusline" ? "quota" : json["hook_event_name"] as? String ?? "Notification", notificationType: json["notification_type"] as? String, project: (json["cwd"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent }, terminal: env["TERM_PROGRAM"], tty: tty, terminalSession: env["ITERM_SESSION_ID"], quota: mode == "statusline" ? QuotaSnapshot.claude(json) : nil)
    if let data = try? JSONEncoder().encode(event) {
        try? CrestPaths.save(data, to: CrestPaths.inbox.appendingPathComponent(UUID().uuidString + ".json"))
    }
    if mode == "statusline" {
        let previous = CrestPaths.root.appendingPathComponent("previous-statusline.json")
        if let data = try? Data(contentsOf: previous), let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let command = config["command"] as? String, !command.contains("crest-bridge") {
            let p = Process(); let input = Pipe(); p.executableURL = URL(fileURLWithPath: "/bin/sh"); p.arguments = ["-c", command]; p.standardInput = input; p.standardOutput = FileHandle.standardOutput; p.standardError = FileHandle.nullDevice
            if (try? p.run()) != nil {
                try? input.fileHandleForWriting.write(contentsOf: payload); try? input.fileHandleForWriting.close()
                DispatchQueue.global().asyncAfter(deadline: .now() + 2) { if p.isRunning { p.terminate() } }
                p.waitUntilExit()
            }
        } else {
            let quota = QuotaSnapshot.claude(json)
            print(quota.windows.isEmpty ? "Crest connected" : quota.windows.map { "\($0.label): \(Int($0.remaining))% left" }.joined(separator: " · "))
        }
    }
}
// Hook mode deliberately returns no approval decision and always succeeds.
