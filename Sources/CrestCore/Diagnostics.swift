import Foundation

/// An allowlist, never a serialized app model, log dump, or preference dictionary.
public struct DiagnosticsReport: Encodable {
    public let schemaVersion = 1
    public let appVersion: String
    public let build: String
    public let osVersion: String
    public let architecture: String
    public let displayCount: Int
    public let hasNotchedDisplay: Bool
    public let features: [String: Bool]
    public init(appVersion: String, build: String, osVersion: String, architecture: String, displayCount: Int, hasNotchedDisplay: Bool, features: [String: Bool]) {
        self.appVersion = appVersion; self.build = build; self.osVersion = osVersion; self.architecture = architecture
        self.displayCount = displayCount; self.hasNotchedDisplay = hasNotchedDisplay
        let allowed: Set<String> = ["codexConnected", "clipboardEnabled", "calendarEnabled", "updatesConfigured", "mediaAvailable", "audioAvailable", "brightnessAvailable", "hardwareKeysEnabled", "globalShortcutEnabled", "reduceMotion", "reduceTransparency"]
        self.features = features.filter { allowed.contains($0.key) }
    }
    public func data() throws -> Data { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; return try encoder.encode(self) }
}
